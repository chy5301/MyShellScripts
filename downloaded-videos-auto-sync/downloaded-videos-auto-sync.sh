#!/bin/bash

# 源目录和目标目录
SOURCE_DIR="${SOURCE_DIR:-/volume1/downloads/Videos}"
DEST_DIR="${DEST_DIR:-/volume2/@home/chy/Videos}"

# 最大重试次数和初始重试间隔
MAX_RETRIES="${MAX_RETRIES:-3}"
INITIAL_RETRY_DELAY="${INITIAL_RETRY_DELAY:-1}"

# 用户和组&权限
TARGET_USER="${TARGET_USER:-chy}"
TARGET_GROUP="${TARGET_GROUP:-admin}"
TARGET_PERMISSIONS="${TARGET_PERMISSIONS:-770}"

# 在源目录下使用 inotifywait 监控文件变化（只监控新增文件）
inotifywait -m -r -e create -e moved_to --format "%w%f" "${SOURCE_DIR}" | while read -r NEW_FILE
do
    # 获取相对路径
    RELATIVE_PATH="${NEW_FILE#${SOURCE_DIR}/}"
    
    # 目标文件路径
    TARGET_FILE="${DEST_DIR}/${RELATIVE_PATH}"

    # 获取目标目录的父目录路径
    TARGET_DIR=$(dirname "${TARGET_FILE}")

    # 初始化重试计数器
    RETRY_COUNT=0

    # 重试循环
    while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
        # 确保目标目录存在，并设置正确的所有者、组和权限
        install -d -m "${TARGET_PERMISSIONS}" -o "${TARGET_USER}" -g "${TARGET_GROUP}" "${TARGET_DIR}"
        
        # 使用 rsync 同步新文件到目标目录
        rsync -rlptv --ignore-existing --no-whole-file \
        --exclude="*.part" --exclude="*.crdownload" --exclude="*.!qB" --exclude="*.ug-tmp" \
        --chown="${TARGET_USER}:${TARGET_GROUP}" --chmod="${TARGET_PERMISSIONS}" "${NEW_FILE}" "${TARGET_FILE}"
        
        # 获取 rsync 的退出状态码
        RSYNC_EXIT_CODE=$?

        if [ $RSYNC_EXIT_CODE -eq 0 ]; then
            # 如果同步成功，输出成功信息并跳出重试循环
            echo "同步完成: ${NEW_FILE} -> ${DEST_DIR}"
            break
        else
            # 如果同步失败，增加重试计数器并输出错误信息
            RETRY_COUNT=$((RETRY_COUNT + 1))
            echo "同步失败: ${NEW_FILE} 状态码: ${RSYNC_EXIT_CODE} 重试: ${RETRY_COUNT}/${MAX_RETRIES}"
            
            # 如果达到最大重试次数，输出最终失败信息
            if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
                echo "同步失败: ${NEW_FILE} 状态码: ${RSYNC_EXIT_CODE} 已达到最大重试次数"
            else
                # 动态调整重试间隔
                sleep $((INITIAL_RETRY_DELAY * RETRY_COUNT))
            fi
        fi
    done
done