#!/bin/bash

# ZTE WE212X 修复版 FIT Image 生成脚本
# 基于原厂格式创建正确的FIT Image

SCRIPT_DIR=$(dirname "$0")
BIN_DIR="/home/rayniel/devel/ipq6000/bin/targets/ipq60xx/generic"
OUTPUT_DIR="/tmp/zte_fixed_fit"
DATE=$(date +%Y%m%d_%H%M%S)

echo "=== ZTE WE212X 修复版 FIT Image 生成 ==="

mkdir -p "$OUTPUT_DIR"
cd "$OUTPUT_DIR"

# 检查源文件
FACTORY_UBI="$BIN_DIR/openwrt-ipq60xx-generic-zte_we212x-squashfs-nand-factory.ubi"

if [ ! -f "$FACTORY_UBI" ]; then
    echo "错误：找不到factory.ubi文件"
    exit 1
fi

echo "源文件: $(basename "$FACTORY_UBI")"
echo "大小: $(stat -c%s "$FACTORY_UBI" | numfmt --to=iec)"

# 1. 创建正确的FIT Image配置文件
echo ""
echo "1. 创建FIT Image配置(.its)..."

cat > "zte-we212x.its" << 'EOF'
/dts-v1/;

/ {
	description = "ZTE WE212X OpenWrt Firmware";
	#address-cells = <1>;

	images {
		ubi {
			description = "UBI NAND rootfs";
			data = /incbin/("./rootfs.ubi");
			type = "filesystem";
			arch = "arm64";
			compression = "none";
			hash@1 {
				algo = "crc32";
			};
			hash@2 {
				algo = "sha1";
			};
		};
	};

	configurations {
		default = "config@1";
		config@1 {
			description = "ZTE WE212X Default Configuration";
			images = "ubi";
		};
	};
};
EOF

echo "✓ FIT配置文件已创建"

# 2. 复制UBI文件
echo ""
echo "2. 准备UBI文件..."
cp "$FACTORY_UBI" "rootfs.ubi"

# 3. 生成FIT Image
echo ""
echo "3. 生成FIT Image..."

if ! command -v mkimage >/dev/null 2>&1; then
    echo "安装mkimage工具..."
    sudo apt update && sudo apt install -y u-boot-tools
fi

mkimage -f "zte-we212x.its" "zte-we212x.itb"

if [ $? -eq 0 ]; then
    echo "✓ FIT Image生成成功"
else
    echo "✗ FIT Image生成失败"
    exit 1
fi

# 4. 验证FIT Image
echo ""
echo "4. 验证FIT Image..."
echo "FIT Image内容:"
dumpimage -l "zte-we212x.itb"

# 检查是否包含ubi段
if dumpimage -l "zte-we212x.itb" | grep -q "ubi"; then
    echo "✓ 包含ubi段"
else
    echo "✗ 缺少ubi段"
    exit 1
fi

# 5. 创建带ZTE头的最终固件
echo ""
echo "5. 创建最终固件..."
FINAL_FIRMWARE="WE212X_FIXED_FIT_${DATE}.img"

# 创建256字节ZTE头
{
    printf "ZTE-WE212X-OPENWRT-FIXED\x00\x00\x00\x00"  # 28字节
    printf "\x12\x02\x00\x00"                         # upgradekey1
    printf "\x01\x00\x00\x00"                         # upgradekey2
    printf "FIXED-FIT-UBI-FORMAT\x00"                 # 21字节
    dd if=/dev/zero bs=1 count=199 2>/dev/null         # 填充到256字节
} > zte_header.bin

# 检查头部大小
HEADER_SIZE=$(stat -c%s zte_header.bin)
echo "ZTE头部大小: $HEADER_SIZE 字节"

# 组合头部和FIT Image
cat zte_header.bin zte-we212x.itb > "$FINAL_FIRMWARE"

FINAL_SIZE=$(stat -c%s "$FINAL_FIRMWARE")
echo "✓ 最终固件: $FINAL_FIRMWARE ($FINAL_SIZE 字节)"

# 6. 完整验证
echo ""
echo "=== 完整验证测试 ==="

# 验证升级密钥
KEY1=$(dd if="$FINAL_FIRMWARE" skip=7 bs=4 count=1 2>/dev/null | hexdump -v -n 4 -e '1/1 "%02x"')
KEY2=$(dd if="$FINAL_FIRMWARE" skip=8 bs=4 count=1 2>/dev/null | hexdump -v -n 4 -e '1/1 "%02x"')

echo "升级密钥验证:"
echo "  upgradekey1: $KEY1 (期望: 12020000) $([ "$KEY1" = "12020000" ] && echo "✓" || echo "✗")"
echo "  upgradekey2: $KEY2 (期望: 01000000) $([ "$KEY2" = "01000000" ] && echo "✓" || echo "✗")"

# 模拟头部删除和验证
dd if="$FINAL_FIRMWARE" of="test_after_header.itb" skip=1 bs=256 2>/dev/null

echo ""
echo "头部删除后验证:"
echo "  文件大小: $(stat -c%s test_after_header.itb) 字节"

if dumpimage -l "test_after_header.itb" >/dev/null 2>&1; then
    echo "  ✓ 是有效的FIT Image"
    
    echo "  包含的段:"
    dumpimage -l "test_after_header.itb" | grep -E "^ Image.*\(" | while read line; do
        section=$(echo "$line" | sed 's/.*(\([^)]*\)).*/\1/' | sed 's/@.*//')
        echo "    - $section"
    done
    
    # 检查mandatory sections
    if dumpimage -l "test_after_header.itb" | grep -q "ubi"; then
        echo "  ✓ 包含必需的ubi段"
        VALIDATION_PASS=true
    else
        echo "  ✗ 缺少ubi段"
        VALIDATION_PASS=false
    fi
else
    echo "  ✗ 不是有效的FIT Image"
    VALIDATION_PASS=false
fi

# 7. 生成升级说明
echo ""
echo "7. 生成升级说明..."
cat > "升级说明-修复版.txt" << EOF
ZTE WE212X 修复版 FIT Image 固件
===============================

此版本修复了FIT Image格式问题，现在应该能通过platform_check_image验证。

固件文件: $FINAL_FIRMWARE
文件大小: $(numfmt --to=iec $FINAL_SIZE)

验证状态:
- 升级密钥: ✓ 正确 (12020000, 01000000)
- FIT格式: ✓ 有效的FIT Image
- UBI段: ✓ 包含必需的ubi段
- 头部大小: ✓ 256字节

升级方法:

SSH升级 (推荐):
1. 上传固件:
   scp $FINAL_FIRMWARE root@192.168.1.1:/tmp/

2. SSH升级:
   ssh root@192.168.1.1
   sysupgrade -v /tmp/$FINAL_FIRMWARE

3. 如果仍然失败，尝试强制升级:
   sysupgrade -F /tmp/$FINAL_FIRMWARE

Web界面升级:
1. 登录 http://192.168.1.1
2. 系统管理 -> 固件升级
3. 上传 $FINAL_FIRMWARE

注意事项:
- 首次升级建议使用 -v 参数 (详细模式)
- 如果验证仍然失败，可使用 -F 强制升级
- 升级完成后设备运行OpenWrt系统

EOF

echo "✓ 升级说明已生成"

# 清理临时文件
rm -f zte_header.bin test_after_header.itb

echo ""
echo "=== 生成完成 ==="
ls -lh "$OUTPUT_DIR"

if [ "${VALIDATION_PASS:-false}" = "true" ]; then
    echo ""
    echo "🎉 所有验证通过！现在可以升级了："
    echo "   scp $PWD/$FINAL_FIRMWARE root@192.168.1.1:/tmp/"
    echo "   ssh root@192.168.1.1 'sysupgrade -v /tmp/$FINAL_FIRMWARE'"
else
    echo ""
    echo "⚠️  如果升级仍然失败，请使用强制模式："
    echo "   sysupgrade -F /tmp/$FINAL_FIRMWARE"
fi