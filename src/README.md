# OriginCar SDK

## 项目简介

OriginCar SDK 是面向 OriginCar 智能车的 ROS 2 运行工作空间，适用于 Ubuntu 22.04 AArch64（ARM64）平台。工作空间整合了底盘控制、激光雷达、USB 相机、机器人模型、地图定位、Nav2 导航、多航点巡航、二维码识别、图像分析和 RViz 可视化。

系统可以使用 N10 或 VP100 激光雷达，通过 AMCL 在已知地图中定位，并基于 Nav2 与自定义路径跟随节点完成巡航。二维码结果可以参与路线方向选择，图像分析节点可以在指定航点获取相机图像并发布分析结果，控制面板用于显示任务状态和发送导航启动信号。

## 技术架构

运行平台：

- Ubuntu 22.04 AArch64（ARM64）
- ROS 2 Humble
- TROS Humble
- Nav2、RViz2、robot_localization
- N10 或 VP100 激光雷达
- OriginCar 串口底盘和 USB 相机

系统分为以下层次：

| 层次 | 功能 |
| --- | --- |
| 设备接入层 | 串口底盘、N10/VP100 雷达、USB 相机 |
| 机器人模型层 | URDF、TF、joint_state_publisher、robot_state_publisher |
| 定位与地图层 | 地图服务器、AMCL、EKF、禁行区地图 |
| 导航控制层 | Nav2、自定义路径跟随、多航点任务、避障与恢复 |
| 感知交互层 | 二维码检测、图像分析、控制面板 |
| 可视化层 | RViz 地图、定位、路径、雷达和机器人状态显示 |

主要 ROS 2 包：

| 包 | 作用 |
| --- | --- |
| `origincar_base` | 底盘串口通信、里程计、底盘启动和设备编排 |
| `origincar_description` | 机器人 URDF、xacro 和 mesh 模型 |
| `origincar_msg` | OriginCar 自定义 ROS 消息 |
| `origincar_system` | Nav2 启动、多航点导航、路径跟随和控制面板 |
| `qr_detector` | 相机二维码检测与结果发布 |
| `aliyun_image_analyzer` | 航点图像分析与结果发布 |
| `lslidar_driver` / `lslidar_msgs` | N10 激光雷达驱动和消息 |
| `vp100_ros2` | VP100 激光雷达驱动 |

默认启动顺序为：底盘与传感器启动、二维码和图像节点启动、Nav2 与 AMCL 启动、RViz 启动、控制面板启动，最后加载多航点导航任务并等待启动信号。

## 目录结构

```text
origincar_sdk/
├── bin/          # 导航启动入口
├── install/      # ROS 2 安装空间、节点、库和包资源
├── libexec/      # SDK 运行载荷
├── resources/    # 地图、RViz、导航、底盘和雷达配置
├── install.sh    # 一键安装脚本
└── README.md
```

`resources` 目录按用途划分：

```text
resources/
├── base/          # EKF 和 IMU 参数
├── lidar/         # N10 和 VP100 参数
├── maps/          # 主地图和禁行区地图
├── navigation/    # Nav2 参数和航点
└── rviz/          # RViz 配置
```

## 安装

在解压后的 SDK 根目录执行：

```bash
bash ./install.sh
```

脚本默认安装到 `/userdata/origincar_sdk`，并创建 `origincar-start` 命令。非 root 用户运行时会自动调用 `sudo`。

指定其他安装目录：

```bash
bash ./install.sh --prefix /userdata/origincar_sdk_test
```

只安装 SDK、不创建系统命令：

```bash
bash ./install.sh --prefix /userdata/origincar_sdk --no-command-links
```

## 启动

安装后启动完整导航系统：

```bash
origincar-start
```

不安装、直接从解压目录启动：

```bash
bash ./bin/start_navigation
```

默认使用 N10 雷达。切换为 VP100：

```bash
LIDAR_TYPE=vp100 origincar-start
```

需要启用图像分析时，在启动前设置 API Key：

```bash
export DASHSCOPE_API_KEY="your-api-key"
origincar-start
```
