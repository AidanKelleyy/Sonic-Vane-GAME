extends RefCounted


static func child_conditions(tree: AnimationNodeBlendTree, path: String, child: StringName, conditions: Array) -> Array:
	var result: Array = conditions.duplicate(true)
	var connections: Array = tree.get("node_connections")
	var pending: Array[StringName] = [child]
	var visited: Dictionary[StringName, bool] = {}
	while not pending.is_empty():
		var source: StringName = pending.pop_back()
		if visited.has(source):
			continue
		visited[source] = true
		for index: int in range(0, connections.size(), 3):
			if StringName(connections[index + 2]) != source:
				continue
			var target: StringName = StringName(connections[index])
			var node: AnimationNode = tree.get_node(target)
			if node is AnimationNodeTransition:
				result.append({"selector_path": path + "/" + String(target) + "/current_state", "selector_state": node.get_input_name(int(connections[index + 1]))})
			elif node is AnimationNodeTimeScale or node is AnimationNodeTimeSeek:
				pending.append(target)
	return result


static func selector_matches(tree: AnimationTree, condition: Dictionary) -> bool:
	return StringName(tree.get(condition["selector_path"])) == StringName(condition["selector_state"])
