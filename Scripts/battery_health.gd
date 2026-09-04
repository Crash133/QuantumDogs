extends ProgressBar


func _on_health_component_health_changed(amount: float, curr_health: float, percentage: float) -> void:
	value = percentage
