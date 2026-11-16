#ifndef QUANTUM_DOGS_HIT_MANAGER_H
#define QUANTUM_DOGS_HIT_MANAGER_H

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/string_name.hpp>
#include <godot_cpp/variant/quaternion.hpp>
#include <godot_cpp/variant/transform3d.hpp>
#include <godot_cpp/variant/vector3.hpp>

#include <deque>
#include <unordered_map>
#include <unordered_set>
#include <vector>

namespace godot {

class HitManager : public RefCounted {
	GDCLASS(HitManager, RefCounted)

	public:
	static constexpr size_t MAX_HURTBOXES = 8192;
	static constexpr size_t MAX_HITBOXES = 1024;
	enum ProfileShape { SPHERE, CAPSULE, BOX, CONE, RING };
	struct Hurtbox {
		Vector3 position;
		float radius = 0.5f;
		float height = 1.0f;
		int32_t layer = 1;
	};
	struct TrailPose {
		Transform3D transform;
		Transform3D previous_transform;
		bool swept = false;
		double age = 0.0;
		Quaternion start_rotation;
		Quaternion end_rotation;
		double rotation_angle = 0.0;
		double translation_distance = 0.0;
	};
	struct Hitbox {
		Transform3D transform;
		Transform3D previous_transform;
		ProfileShape shape = SPHERE;
		Vector3 size = Vector3(1.0, 1.0, 1.0);
		std::vector<float> decay_curve;
		int32_t linger_ticks = 8;
		uint32_t collision_mask = UINT32_MAX;
		bool active = false;
		bool has_previous = false;
		std::deque<TrailPose> trail;
		std::unordered_set<int32_t> hit_ids;
	};

	private:
	std::vector<int32_t> hurtbox_ids;
	std::vector<Vector3> hurtbox_positions;
	std::vector<float> hurtbox_radii;
	std::vector<float> hurtbox_heights;
	std::vector<int32_t> hurtbox_layers;
	std::unordered_map<int32_t, size_t> hurtbox_slots;
	std::unordered_map<int32_t, Hitbox> hitboxes;
	int32_t next_hurtbox_id = 1;
	int64_t sweep_exhaustions = 0;
	Hurtbox hurtbox_at(size_t index) const;
	Array step_internal(const std::unordered_map<int32_t, double> *age_deltas, bool deduplicate_stationary);

protected:
	static void _bind_methods();

public:
	int32_t register_hurtbox(Vector3 position, double radius, double height, int32_t layer);
	void update_hurtboxes(PackedInt32Array ids, PackedVector3Array positions);
	void unregister_hurtbox(int32_t id);
	void configure_hitbox(int32_t id, StringName shape, Vector3 size, int32_t linger_ticks, PackedFloat32Array decay_curve);
	void unregister_hitbox(int32_t id);
	void set_hitbox_mask(int32_t id, int64_t mask);
	void activate_hitbox(int32_t id, bool active);
	void set_hitbox_transform(int32_t id, Transform3D transform);
	void refresh(int32_t id);
	void discard_hitbox_trails(int32_t id);
	Array step();
	Array step_with_ages(PackedInt32Array hitbox_ids, PackedFloat32Array age_tick_deltas);
	Dictionary get_debug_snapshot() const;
	int64_t get_sweep_exhaustions() const { return sweep_exhaustions; }
	Dictionary raycast(Vector3 origin, Vector3 direction, double distance, double cone_degrees, int64_t mask, int32_t preferred_id);
};

} // namespace godot

#endif
