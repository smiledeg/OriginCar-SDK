from launch.exit_handler import ignore_exit_handler, restart_exit_handler
from ros2run.api import get_executable_path


def launch(launch_descriptor, argv):
    ld = launch_descriptor
    package = 'vp100_ros2'
    ld.add_process(
        cmd=[get_executable_path(package_name=package, executable_name='vp100_ros2_node')],
        name='vp100_ros2_node',
        exit_handler=restart_exit_handler,
    )
    package = 'tf2_ros'
    ld.add_process(
        cmd=[
            get_executable_path(
                package_name=package, executable_name='static_transform_publisher'),
            '-0.03', '-0.0025', '0.16',
            '0', '0', '-1', '0',
            'base_link',
            'laser_frame'
        ],
        name='static_tf_pub_laser',
        exit_handler=restart_exit_handler,
    )
    return ld
