# OriginCar 智能导航系统 — 技术方案文档

---

## 1. 整体系统架构说明

### 1.1 系统定位

OriginCar 是一套基于 ROS 2 Humble 的自主导航智能车系统，面向室内巡检、多航点巡航和竞赛任务场景。系统整合了底盘控制、激光雷达定位、Nav2 全局导航、多航点任务调度、二维码识别、图像 AI 分析等能力。

### 1.2 分层架构

- **任务调度层**: multi_point_nav / smooth_path_follower — 航点序列、倒车逻辑、二维码方向选择、图像触发
- **导航控制层**: Nav2 (Planner + Controller + Recovery) / 自定义 smooth_path_follower (纯追踪 + 避障)
- **定位与建图层**: AMCL 定位 + EKF 融合 + 地图服务器 + 禁行区
- **感知交互层**: 二维码检测 (qr_detector) + 图像分析 (阿里云 DashScope) + 控制面板
- **设备接入层**: 串口底盘 (origincar_base) + N10/VP100 激光雷达 + USB 相机
- **可视化层**: RViz2 (地图、定位、路径、雷达、机器人模型)

### 1.3 数据流

`
激光雷达(/scan) ──┬──> AMCL ──> /amcl_pose ──> EKF
                  │                               │
                  └──> Nav2 Costmap               ├──> /odom_combined ──> Nav2 Controller
                                                  │
底盘(/odom) ──────────────────────────────────────┘

USB相机 ──> qr_detector ──> /qr_info ──> smooth_path_follower (方向选择)
         ──> aliyun_image_analyzer ──> /image_ai ──> control_panel
`

### 1.4 启动流程

1. **底盘与传感器** — origincar_base 启动串口通信、发布里程计；激光雷达驱动启动、发布 /scan
2. **二维码与图像节点** — qr_detector 监听相机并发布 /qr_info；aliyun_image_analyzer 就绪
3. **Nav2 + AMCL** — 加载地图、禁行区滤波器、初始位姿发布；Nav2 栈启动
4. **RViz** — 可视化地图、机器人模型、雷达扫描、路径
5. **导航任务** — smooth_path_follower 或 multi_point_nav 加载航点、等待启动信号
6. **发车** — 控制面板或手动触发 /nav_start

---

## 2. 硬件选型与连接方式

### 2.1 计算平台

- **处理器**: ARM64 (AArch64)
- **操作系统**: Ubuntu 22.04 LTS
- **ROS 版本**: ROS 2 Humble / TROS Humble

### 2.2 底盘

- **型号**: OriginCar 专用底盘
- **通信方式**: 串口 (Serial)
- **控制接口**: 发布 /cmd_vel (geometry_msgs/Twist)
- **里程计**: 发布 /odom (nav_msgs/Odometry)
- **运动学**: 差速/阿克曼，支持前进和倒车

### 2.3 激光雷达

| 参数 | N10 雷达 | VP100 雷达 |
|------|----------|-----------|
| 型号 | LSLIDAR N10 | VP100 |
| 接口 | 串口 (/dev/ttyACM1) | 串口 (/dev/ttyUSB0) |
| 话题 | /scan | /scan |
| 坐标系 | laser_link | laser_frame |
| 范围 | 0.2 - 200m | 0.001 - 64m |
| 启动方式 | origincar-start | LIDAR_TYPE=vp100 origincar-start |

### 2.4 相机

- **类型**: USB 相机
- **用途**: 二维码识别、图像采集
- **话题**: /image（压缩图像）

### 2.5 传感器融合（EKF）

- **包**: robot_localization
- **输入**: /odom (vx, vy, vyaw) + /imu/data (yaw)
- **输出**: /odom_combined
- **频率**: 15Hz
- **坐标系**: map -> odom_combined -> base_footprint -> base_link

---

## 3. 软件系统设计思路

### 3.1 双模导航架构

#### 方案 A: smooth_path_follower（自定义纯追踪）

- 直接读取 TF 中的机器人位姿，按航点序列逐一导航
- 自定义 Pure Pursuit 算法，根据前方目标点计算线速度和角速度
- 实时读取 /scan 数据，前方障碍物触发减速/停车/绕行
- 优势: 航点控制精细、支持倒车、可逐航点调速

#### 方案 B: multi_point_nav（Nav2 全局导航）

- 通过 Nav2 Action 接口发送目标点
- Nav2 SmacPlannerHybrid 全局规划 + RegulatedPurePursuitController 局部跟踪
- Nav2 Costmap + Recovery Behavior
- 优势: 全局最优路径、自动避障恢复

### 3.2 航点配置系统

航点定义在 waypoints.yaml，支持顺时针和逆时针两套路线：

`yaml
routes:
  clockwise:
    - name: point_01
      x: 3.67553       # map 坐标系下的目标 x
      y: 0.936773       # map 坐标系下的目标 y
      yaw: 0.773551     # 目标朝向角 (rad)
      pass_radius: 0.5  # 到达判定半径 (m)
    - name: point_02
      x: 3.70349
      y: 0.265574
      yaw: 2.420
      pass_radius: 0.8
      reverse: true              # 倒车抵达
      reverse_pass_radius: 0.8   # 倒车到达判定半径
`

**航点属性说明**:

| 属性 | 说明 |
|------|------|
| name | 航点名称 |
| x, y | map 坐标系下的位置 |
| yaw | 目标朝向角 (弧度) |
| pass_radius | 到达判定半径 |
| reverse | 是否倒车抵达 |
| reverse_pass_radius | 倒车到达判定半径 |

### 3.3 二维码方向选择

- 起点附近设有二维码，编码顺/逆时针信息
- qr_detector 读取二维码后发布 /qr_info
- smooth_path_follower 根据二维码值自动选择顺/逆时针路线
- 一旦选择后锁定 (lock_qr_direction_after_select)

### 3.4 图像 AI 分析

- 在指定航点（默认 point_07）触发相机拍照
- 图像发送至阿里云 DashScope API 进行分析
- 结果发布到 /image_ai 话题
- 控制面板显示分析结果

### 3.5 禁行区系统

- 使用 Nav2 KeepoutFilter 加载禁行区地图 (race_keepout.pgm)
- 导航规划和局部控制均会避开禁行区
- 禁行区地图与主地图分辨率、原点一致

---

## 4. 关键任务实现策略

### 4.1 定位策略

**AMCL 配置**:

| 参数 | 值 | 说明 |
|------|-----|------|
| laser_model_type | likelihood_field | 激光模型类型 |
| max_particles | 1000 | 最大粒子数 |
| min_particles | 200 | 最小粒子数 |
| initial_pose | (-0.038, -0.050, 0.017) | 初始位姿 |
| update_min_d | 0.05m | 最小移动距离触发更新 |
| update_min_a | 0.05rad | 最小旋转角度触发更新 |

**EKF 融合**: 里程计提供 vx, vy, vyaw；IMU 提供 yaw；输出 /odom_combined

### 4.2 路径跟踪策略（smooth_path_follower）

**速度控制**:

| 参数 | 值 | 说明 |
|------|-----|------|
| linear_speed | 0.45 m/s | 直行基础速度 |
| channel_linear_speed | 0.38 m/s | 特殊航点速度 |
| channel_waypoint_ranges | 1-1,11-11 | 慢速航点范围 |
| max_angular_z | 2.0 rad/s | 最大角速度 |
| turn_angular_gain | 1.6 | 转弯角速度增益 |
| turn_min_speed_scale | 0.75 | 转弯时最低速度比例 |

**前视距离与到达判定**:

| 参数 | 值 | 说明 |
|------|-----|------|
| lookahead_distance | 0.50m | 前视距离 |
| pass_radius | 0.35m | 默认到达判定半径 |
| NAV2_SUCCESS_DISTANCE_TOLERANCE | 0.60m | Nav2 模式到达容差 |

**避障策略**:

| 参数 | 值 | 说明 |
|------|-----|------|
| obstacle_stop_distance | 0.30m | 停车距离 |
| obstacle_slow_distance | 0.60m | 减速距离 |
| obstacle_avoid_distance | 0.50m | 绕行距离 |
| front_angle_deg | 35.0 | 前方检测角度 |

**倒车逻辑**:

| 参数 | 值 | 说明 |
|------|-----|------|
| reverse_min_speed_scale | 0.65 | 倒车最低速度比例 |
| backup_speed | 0.35 m/s | 倒车速度 |
| backup_trigger_time | 1.0s | 倒车触发等待时间 |
| backup_duration | 0.5s | 倒车持续时间 |

### 4.3 Nav2 全局导航配置

**Planner — SmacPlannerHybrid**:

| 参数 | 值 |
|------|-----|
| motion_model | DUBIN |
| minimum_turning_radius | 0.25m |
| max_planning_time | 3.0s |
| max_iterations | 100000 |
| reverse_penalty | 10.0 |
| cost_penalty | 100.0 |

**Controller — RegulatedPurePursuitController**:

| 参数 | 值 |
|------|-----|
| desired_linear_vel | 0.58 m/s |
| lookahead_dist | 0.80m |
| min_lookahead_dist | 0.55m |
| max_lookahead_dist | 1.20m |
| use_collision_detection | true |
| use_regulated_linear_velocity_scaling | true |
| approach_velocity_scaling_dist | 0.35m |

**Recovery Behavior**:

| 动作 | 说明 |
|------|------|
| BackUp | 倒退 0.3m，速度 0.35 m/s |
| Wait | 等待 2s |
| ClearCostmap | 清除 3m 范围内的代价地图 |

### 4.4 地图配置

| 地图 | 文件 | 分辨率 | 用途 |
|------|------|--------|------|
| 主地图 | race_modify.pgm/.yaml | 0.05 m/pix | AMCL 定位 + Nav2 全局规划 |
| 禁行区 | race_keepout.pgm/.yaml | 0.05 m/pix | Nav2 KeepoutFilter 避障 |

---

## 5. 与竞赛任务及规则的适配说明

### 5.1 赛道概述

赛道为室内封闭环形路线，包含起点/终点区域（二维码识别区）、多个转弯点、直道和弯道混合、禁行区（虚拟墙）。

### 5.2 航点规划

共 11 个航点，覆盖完整赛道：

| 航点 | 特殊功能 | 说明 |
|------|----------|------|
| point_01 | 二维码识别区 | 慢速通过，读取方向信息 |
| point_02 | 倒车点 | reverse=true，倒车到达指定位置 |
| point_03 | 转弯过渡 | pass_radius=0.2（精确通过） |
| point_04-09 | 常规巡航点 | 中等检测范围 |
| point_10 | 经过点 | pass_radius=0.35（放宽检测） |
| point_11 | 终点 | 回到起点区域 |

### 5.3 方向自适应

- 二维码在起点处读取
- QR 值 = 1 -> 顺时针路线
- QR 值 = 2 -> 逆时针路线
- 选择后锁定，整圈使用同一方向

### 5.4 虚拟墙/禁行区适配

- 禁行区地图覆盖赛道边界和不允许通行的区域
- KeepoutFilter 在规划和控制层同时生效
- 确保车辆不会抄近路或进入禁区

### 5.5 关键调优参数

**速度优化**:
- 直道速度可提升至 0.75 m/s
- 转弯保持 0.45 m/s 安全速度
- point_01 和 point_11 使用慢速确保二维码识别

**精度优化**:
- 关键转弯点 pass_radius = 0.2-0.3
- 倒车点 pass_radius = 0.8（宽松检测避免卡死）
- 经过点 pass_radius = 0.35（快速通过）

---

## 附录 A: 文件结构

`
origincar_export/
├── bin/                              # 启动脚本
│   ├── start_navigation              # 主启动入口
│   ├── start_qr_navigation           # 二维码导航启动
│   └── start_control_panel.sh        # 控制面板启动
├── launch/                           # ROS2 Launch 文件
│   ├── smooth_path_follower.launch.xml
│   ├── multi_point_nav.launch.xml
│   ├── nav2_amcl_keepout.launch.xml
│   └── map_only.launch.xml
├── resources/                        # 配置文件
│   ├── base/ekf.yaml, imu.yaml
│   ├── lidar/lsn10.yaml, vp100.yaml
│   ├── maps/race_modify.*, race_keepout.*
│   ├── navigation/controller_params_keepout.yaml, waypoints.yaml
│   └── rviz/default.rviz, vp100.rviz
├── install.sh
└── README.md
`

## 附录 B: ROS 2 关键话题

| 话题 | 类型 | 说明 |
|------|------|------|
| /scan | LaserScan | 激光雷达扫描 |
| /odom | Odometry | 底盘里程计 |
| /odom_combined | Odometry | EKF 融合里程计 |
| /cmd_vel | Twist | 速度控制指令 |
| /qr_info | String | 二维码识别结果 |
| /image | CompressedImage | 相机压缩图像 |
| /image_ai | String | 图像 AI 分析结果 |
| /nav_start | Int32 | 启动信号 |
| /amcl_pose | PoseWithCovarianceStamped | AMCL 定位 |

## 附录 C: 坐标系

| 坐标系 | 说明 |
|--------|------|
| map | 全局固定坐标系（地图） |
| odom_combined | 里程计坐标系（短期精确） |
| base_footprint | 机器人底座坐标系 |
| base_link | 机器人中心坐标系 |
| laser_link / laser_frame | 激光雷达坐标系 |

---

*文档版本: v1.0*
*生成日期: 2026-07-23*
*系统平台: Ubuntu 22.04 ARM64 / ROS 2 Humble*