extends Resource
class_name CameraFlareElement

## Texture drawn along the source-to-screen-center axis.
@export var texture: Texture2D
## Position on the flare axis. Zero is the source, one is screen center, and two is the opposite side.
@export_range(-2.0, 3.0, 0.01) var axis_position: float = 0.5
## Diameter as a fraction of viewport height, independent of aspect ratio.
@export_range(0.001, 2.0, 0.001) var diameter: float = 0.3
## Color and maximum opacity of this lens element.
@export var tint: Color = Color(1.0, 1.0, 1.0, 0.35)
