#!/usr/bin/python3

from ament_index_python.packages import get_package_share_directory

from launch import LaunchDescription
from launch_ros.actions import LifecycleNode
from launch_ros.actions import Node
from launch.actions import DeclareLaunchArgument
from launch.substitutions import LaunchConfiguration
from launch.actions import LogInfo

import lifecycle_msgs.msg
import os


def generate_launch_description():
    resources_dir = os.environ['ORIGINCAR_RESOURCES']
    rviz_config_file = os.path.join(resources_dir, 'rviz', 'vp100.rviz')
    parameter_file = LaunchConfiguration('params_file')
    node_name = 'vp100_ros2_node'

    params_declare = DeclareLaunchArgument('params_file',
                                           default_value=os.path.join(
                                               resources_dir, 'lidar', 'vp100.yaml'),
                                           description='FPath to the ROS2 parameters file to use.')

    driver_node = LifecycleNode(package='vp100_ros2',
                                node_executable='vp100_ros2_node',
                                name='vp100_ros2_node',
                                output='screen',
                                emulate_tty=True,
                                parameters=[parameter_file],
                                namespace='/',
                                )
    tf2_node = Node(package='tf2_ros',
                    executable='static_transform_publisher',
                    name='static_tf_pub_laser',
                    arguments=[
                        '--x', '-0.03',
                        '--y', '-0.0025',
                        '--z', '0.16',
                        '--roll', '0',
                        '--pitch', '0',
                        '--yaw', '-3.14159',
                        '--frame-id', 'base_link',
                        '--child-frame-id', 'laser_frame',
                    ],
                    )
    rviz2_node = Node(package='rviz2',
                    executable='rviz2',
                    name='rviz2',
                    arguments=['-d', rviz_config_file],
                    )

    return LaunchDescription([
        params_declare,
        driver_node,
        tf2_node,
        rviz2_node,
    ])
