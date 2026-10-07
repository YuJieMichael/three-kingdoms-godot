# 内城网格与写实建筑更新

版本：0.6.0-dev.10。用户要求内城按格子建设，并采用更写实的古代RTS建筑。开发仅在独立Godot仓库，原网页不部署。

36个实际地块默认按编号排列，电脑6列、手机3列。空地点击后打开按民生、军备、科技分类的建设目录，显示原规则费用、工期和条件；选择只预览，确认才提交该格建设。重复建筑使用各自的实际site，官府与三处保留地沿用原规则。固定城务工具栏、定位官府方便查看长城市。

本轮使用内置image_gen生成新的写实斜俯视建筑，采用灰瓦、木架、石基、土墙与独立院落。实际16种内城建筑与装饰门楼共17个视觉区域；两张图集与五张独立建筑PNG使用原始像素/alpha，没有抠除背景、重采样或下载帝国时代素材。初次图集排列越界版本舍弃；最终核心与民政图集已重排，工业建筑改独立图防止串图。地面另用土石纹理连接道路，建筑保持源图比例并让开名字/等级、施工倒计时与进度条。0级仍为地基，缺图有兼容轮廓。

## 素材与生成记录

最终素材保存于 assets/environment/city/：
city_rts_core_v1.png、city_rts_civic_v1.png、city_rts_smith_v1.png、city_rts_workshop_v1.png、city_rts_beacon_v1.png、city_rts_wall_v1.png、city_rts_post_v1.png、city_ground_rts_v1.png。
实际内置工具prompt及重排prompt见同目录 [RTS_GENERATION_PROMPTS.json](../../assets/environment/city/RTS_GENERATION_PROMPTS.json)。
每个区域、源尺寸与SHA见 [city-rts-art-atlas.json](../../data/city-rts-art-atlas.json)；生成源路径/字节数审计见 [asset-source-audit.json](../qa/evidence/story-016/asset-source-audit.json)。旧素材保留在仓库，导出排除已停用旧图集。

## 验证与边界

相关GDScript检查全部通过，涵盖真实site与重复建筑、触摸拖动取消、建设先选后确认、最新报价/条件守卫、固定工具栏与官府定位，以及旧页导航和输入。原规则桥接23项通过，无需改动vendor或经济/战斗规则。

最终验收见 [qa-summary.json](../qa/evidence/story-016/qa-summary.json)：9组GDScript共5659项、Node23项、原生1316项通过；窗口生命周期修复后客户端111项再次通过。最终包审计196项，两个PCK分别76项通过，并各自在独立QA新档真实确认一次建造。最终网页1280×1000与390×844检查目录、预览、返回、滚动与定位，warning/error0；HTTP18项、revision0、无消费，来源与副本存档摘要保持。原生示例图来自规则产出的准备场景，供检查所有建筑、施工与空地，不代表玩家自然成长或修改玩家存档。Windows EXE和物理手机尚未运行；公网账号与Steam服务仍沿用之前暂缓决定。



## 本机试玩与最终构建

已启动 [新版内城试玩](http://127.0.0.1:17358/)，使用 `.local/city-grid-0610-preview` 的进度副本；进入「城池」后点空地建设，可用「定位官府」找到已有建筑。

最终构建在 `build/city-grid-0610-final/`，两包包含游戏资源、官方Windows Node和原规则服务，私人配置与存档不入包。Windows ZIP SHA-256：`455dc3e190226ae621f77858d01a20e5224f11b030080da9bb2d6d3e62c57285`（101238199字节）；Web ZIP：`58fe3d3398a80fd0115bfe258c932e600c9012a89964049bb116d271d01cbe3d`（73395725字节）。完整manifest与SHA256SUMS已保存于故事证据目录。

实际浏览器发现的旧窗口移除报错已改成hide后延迟queue_free，并在最终导出中重验。导出PCK验证使用macOS Godot加载和独立本机规则服务，不能等同Windows硬件运行。格子与建筑已接入当前游戏；动态居民、建筑等级独立外观、全国州郡和新地形规则不属于本轮更新。
