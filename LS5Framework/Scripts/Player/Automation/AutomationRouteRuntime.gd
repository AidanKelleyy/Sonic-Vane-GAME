extends RefCounted
class_name AutomationRouteRuntime

signal transferred(connection: AutomationRouteConnection, previous: AutomationSession, current: AutomationSession)
signal progress_event(marker: AutomationProgressMarker, body: Node3D, direction: int)

var _controller_ref: WeakRef
var _transfer_span: float = 0.0


func _init(controller: PlayerAutomationController) -> void:
	_controller_ref = weakref(controller)


func capture_input(lateral: float) -> void:
	var controller: PlayerAutomationController = _controller_ref.get_ref() as PlayerAutomationController
	var session: AutomationSession = controller.selected if controller else null
	if not session:
		return
	var source: AutomationSplineCore = session.get_source() as AutomationSplineCore
	if not source:
		return
	var state: Dictionary = session.route_state
	if absf(lateral) < 0.2:
		state["input_armed"] = true
		return
	if not state.get("input_armed", true):
		return
	var threshold: float = 1.1
	var lane: AutomationLaneTrait = lane_trait(source, controller.motion.is_grounded())
	if lane:
		threshold = lane.input_threshold
	for child: Node in source.get_children():
		if child is AutomationRouteConnection and child.enabled and child.choice != AutomationRouteConnection.Choice.DEFAULT:
			threshold = minf(threshold, child.input_threshold)
	if absf(lateral) < threshold:
		return
	state["input_armed"] = false
	state["choice"] = -1 if lateral < 0.0 else 1
	state["choice_time"] = session.elapsed
	state["choice_strength"] = absf(lateral)
	if lane and absf(lateral) >= lane.input_threshold:
		state["lane"] = clampi(int(state.get("lane", lane.initial_lane)) + (-1 if lateral < 0.0 else 1), 0, lane.lane_count - 1)


static func lane_trait(source: AutomationSplineCore, grounded: bool) -> AutomationLaneTrait:
	for component: AutomationPositionTrait in source.position_traits:
		if component and component.applies(grounded):
			return component as AutomationLaneTrait
	return null


static func lane_offset(session: AutomationSession, component: AutomationLaneTrait) -> float:
	return component.offset(int(session.route_state.get("lane", component.initial_lane)))


static func crossings(previous: float, current: float, distance: float, length: float, closed: bool) -> Array[float]:
	var values: Array[float] = []
	if absf(previous - current) < 0.00000001 or length <= 0.0:
		return values
	var first: int = int(floor((minf(previous, current) - distance) / length)) if closed else 0
	var last: int = int(ceil((maxf(previous, current) - distance) / length)) if closed else 0
	if last - first > 64:
		return values
	for lap: int in range(first, last + 1):
		var crossing: float = distance + float(lap) * length
		if (previous < crossing and crossing <= current) or (current <= crossing and crossing < previous):
			values.append(crossing)
	if current < previous:
		values.reverse()
	return values


func advance(session: AutomationSession, previous: float, delta: float, displacement: float) -> void:
	var controller: PlayerAutomationController = _controller_ref.get_ref() as PlayerAutomationController
	var source: AutomationSplineCore = session.get_source() as AutomationSplineCore
	if not source or controller.selected != session or controller.motion.is_suspended():
		return
	# Discontinuities do not emit events or transfer ownership.
	if displacement > maxf(source.recovery_distance, absf(session.signed_speed) * maxf(delta, 0.0) * 3.0 + source.tracking_window):
		session.route_state.clear()
		return
	_transfer_span = displacement
	var current: float = session.unwrapped_progress
	var direction: int = 1 if current > previous else -1
	var events: Array[Dictionary] = []
	var connections: Array[Dictionary] = []
	for child: Node in source.get_children():
		if child is AutomationProgressMarker and child.enabled:
			var id: int = child.get_instance_id()
			var marker_state: Dictionary = session.marker_states.get_or_add(id, {})
			if marker_state.has("last") and child.retrigger == AutomationProgressMarker.Retrigger.REARM_DISTANCE and absf(previous - float(marker_state.last)) >= child.rearm_distance:
				marker_state["armed"] = true
			for point: float in crossings(previous, current, child.progress * source.sampler.length, source.sampler.length, source.sampler.closed):
				if child.permits(direction):
					events.append({"point": point, "marker": child, "state": marker_state})
		elif child is AutomationRouteConnection and child.enabled and child.source_direction == direction:
			for point: float in crossings(previous, current, child.source_progress * source.sampler.length, source.sampler.length, source.sampler.closed):
				connections.append({"point": point, "connection": child})
	events.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.point * direction < b.point * direction)
	connections.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.point * direction < b.point * direction)
	var transfer_point: float = INF if direction > 0 else -INF
	var chosen: AutomationRouteConnection
	for item: Dictionary in connections:
		var connection: AutomationRouteConnection = item.connection
		var choice: int = int(session.route_state.get("choice", 0))
		var requested: int = -1 if connection.choice == AutomationRouteConnection.Choice.LEFT else 1
		var matches: bool = connection.choice != AutomationRouteConnection.Choice.DEFAULT and choice == requested and session.elapsed - float(session.route_state.get("choice_time", -INF)) <= connection.buffer_seconds and float(session.route_state.get("choice_strength", 0.0)) >= connection.input_threshold
		if not matches and connection.choice != AutomationRouteConnection.Choice.DEFAULT:
			continue
		if chosen and not is_equal_approx(item.point, transfer_point):
			break
		if _can_transfer(connection, session):
			if not chosen or (matches and chosen.choice == AutomationRouteConnection.Choice.DEFAULT):
				chosen = connection
				transfer_point = item.point
	for event: Dictionary in events:
		if event.point * direction > transfer_point * direction:
			break
		var marker: AutomationProgressMarker = event.marker
		if not is_instance_valid(marker) or not event.state.get("armed", true):
			continue
		event.state["armed"] = false
		event.state["last"] = event.point
		var body: Node3D = controller.get_body()
		marker.crossed.emit(body, direction)
		if controller.selected != session or not is_instance_valid(source) or not source.enabled or controller.motion.is_suspended():
			return
		if is_instance_valid(marker):
			progress_event.emit(marker, body, direction)
		if controller.selected != session or not is_instance_valid(source) or not source.enabled or controller.motion.is_suspended():
			return
	if is_instance_valid(chosen) and _can_transfer(chosen, session):
		_transfer(chosen, session)


func _can_transfer(connection: AutomationRouteConnection, session: AutomationSession) -> bool:
	var controller: PlayerAutomationController = _controller_ref.get_ref() as PlayerAutomationController
	var destination: AutomationSplineCore = connection.get_destination()
	var body: Node3D = controller.get_body()
	if controller.motion.is_suspended() or not connection.enabled or connection.get_source() != session.get_source() or not destination or not destination.accepts(body) or controller.is_source_blocked(destination):
		return false
	var value: Dictionary = connection.preview()
	if not value.valid:
		return false
	var finish: AutomationSample = _arrival_sample(connection, value.finish)
	if not finish.valid or finish.spatial_error > connection.maximum_gap or (destination.capture_distance > 0.0 and finish.spatial_error > destination.capture_distance):
		return false
	if destination.beyond_open_end(body.global_position, finish):
		return false
	if destination.activation_mode == AutomationSplineCore.ActivationMode.OCCUPANCY and not destination.is_occupied(body):
		return false
	return controller.can_select_transfer(session, destination)


func _arrival_sample(connection: AutomationRouteConnection, entry: AutomationSample) -> AutomationSample:
	var controller: PlayerAutomationController = _controller_ref.get_ref() as PlayerAutomationController
	var body: Node3D = controller.get_body()
	var destination: AutomationSplineCore = connection.get_destination()
	var span: float = maxf(_transfer_span + connection.maximum_gap, 0.01)
	var value: AutomationSample = destination.sampler.closest(body.global_position, entry.distance, span, -1.0, 0.0)
	if value.valid:
		var advance_distance: float = destination.sampler.distance_delta(entry.distance, value.distance) if destination.sampler.closed else value.distance - entry.distance
		if advance_distance * float(connection.destination_direction) < -connection.maximum_gap or absf(advance_distance) > span or body.global_position.distance_to(entry.position) > span:
			value.valid = false
	return value


func _transfer(connection: AutomationRouteConnection, previous: AutomationSession) -> void:
	var controller: PlayerAutomationController = _controller_ref.get_ref() as PlayerAutomationController
	var destination: AutomationSplineCore = connection.get_destination()
	var value: Dictionary = connection.preview()
	var start: AutomationSample = value.start
	var finish: AutomationSample = _arrival_sample(connection, value.finish)
	var old_frame: Basis = Basis(start.normal * float(connection.source_direction), start.up, -start.tangent * float(connection.source_direction))
	var new_frame: Basis = Basis(finish.normal * float(connection.destination_direction), finish.up, -finish.tangent * float(connection.destination_direction))
	var velocity: Vector3 = controller.get_body_velocity()
	var rotated: Vector3 = new_frame * old_frame.transposed() * velocity
	var current: AutomationSession = controller.commit_transfer(previous, destination, finish, connection.destination_direction, rotated)
	if current and is_instance_valid(connection):
		transferred.emit(connection, previous, current)
