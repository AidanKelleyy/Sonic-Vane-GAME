extends Resource
class_name PropCollisionPart

## Convex shape used by a usable damage stage.
@export var shape: Shape3D
## Local pose of this collision part on the prop body.
@export var transform: Transform3D = Transform3D.IDENTITY
