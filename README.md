# easy-nvr-lzcapp

项目使用 LPK v2。每天 23:00 UTC 及手动触发时，GitHub Actions 会使用触发时的毫秒时间戳请求 EasyNVR 官方 `new_version.json`。

自动化以 `version_list[0].version` 作为已发布版本，只处理不低于当前包版本的稳定版本；相同版本用于修复缺失的 Release/商店发布，回退版本会失败关闭。确认版本后，工作流会验证并复制官方 `latest` 的 `linux/amd64` 镜像，创建 `<package-id>-v<version>.lpk` GitHub Release Asset，并分别发布到懒猫官方商店和喵喵商店。
