#include "hit_manager.h"

#include <algorithm>
#include <cmath>
#include <godot_cpp/variant/utility_functions.hpp>

using namespace godot;

static constexpr const char *SHAPE_SPHERE = "sphere";
static constexpr const char *SHAPE_CAPSULE = "capsule";
static constexpr const char *SHAPE_BOX = "box";
static constexpr const char *SHAPE_CONE = "cone";
static constexpr const char *SHAPE_RING = "ring";

static bool shape_is(const StringName &shape, const char *name) {
	return shape == StringName(String(name));
}

void HitManager::_bind_methods() {
	ClassDB::bind_method(D_METHOD("register_hurtbox", "position", "radius", "height", "layer"), &HitManager::register_hurtbox);
	ClassDB::bind_method(D_METHOD("update_hurtboxes", "ids", "positions"), &HitManager::update_hurtboxes);
	ClassDB::bind_method(D_METHOD("unregister_hurtbox", "id"), &HitManager::unregister_hurtbox);
	ClassDB::bind_method(D_METHOD("configure_hitbox", "id", "shape", "size", "linger_ticks", "decay_curve"), &HitManager::configure_hitbox);
	ClassDB::bind_method(D_METHOD("unregister_hitbox", "id"), &HitManager::unregister_hitbox);
	ClassDB::bind_method(D_METHOD("set_hitbox_mask", "id", "mask"), &HitManager::set_hitbox_mask);
	ClassDB::bind_method(D_METHOD("activate_hitbox", "id", "active"), &HitManager::activate_hitbox);
	ClassDB::bind_method(D_METHOD("set_hitbox_transform", "id", "transform"), &HitManager::set_hitbox_transform);
	ClassDB::bind_method(D_METHOD("refresh", "id"), &HitManager::refresh);
	ClassDB::bind_method(D_METHOD("discard_hitbox_trails", "id"), &HitManager::discard_hitbox_trails);
	ClassDB::bind_method(D_METHOD("step"), &HitManager::step);
	ClassDB::bind_method(D_METHOD("step_with_ages", "hitbox_ids", "age_tick_deltas"), &HitManager::step_with_ages);
	ClassDB::bind_method(D_METHOD("get_debug_snapshot"), &HitManager::get_debug_snapshot);
	ClassDB::bind_method(D_METHOD("get_sweep_exhaustions"), &HitManager::get_sweep_exhaustions);
	ClassDB::bind_method(D_METHOD("raycast", "origin", "direction", "distance", "cone_degrees", "mask", "preferred_id"), &HitManager::raycast, DEFVAL(int64_t(UINT32_MAX)), DEFVAL(-1));
}

int32_t HitManager::register_hurtbox(Vector3 position, double radius, double height, int32_t layer) {
	if (hurtbox_ids.size() >= MAX_HURTBOXES || next_hurtbox_id == INT32_MAX) return -1;
	const int32_t id = next_hurtbox_id++;
	hurtbox_slots[id] = hurtbox_ids.size();
	hurtbox_ids.push_back(id);
	hurtbox_positions.push_back(position);
	hurtbox_radii.push_back(static_cast<float>(std::max(0.0, radius)));
	hurtbox_heights.push_back(static_cast<float>(std::max(0.0, height)));
	hurtbox_layers.push_back(layer);
	return id;
}

HitManager::Hurtbox HitManager::hurtbox_at(size_t index) const {
	return {hurtbox_positions[index], hurtbox_radii[index], hurtbox_heights[index], hurtbox_layers[index]};
}

void HitManager::update_hurtboxes(PackedInt32Array ids, PackedVector3Array positions) {
	const int32_t count = std::min(ids.size(), positions.size());
	for (int32_t i = 0; i < count; ++i) {
		auto found = hurtbox_slots.find(ids[i]);
		if (found != hurtbox_slots.end()) hurtbox_positions[found->second] = positions[i];
	}
}

void HitManager::unregister_hurtbox(int32_t id) {
	auto found = hurtbox_slots.find(id);
	if (found == hurtbox_slots.end()) return;
	const size_t slot = found->second;
	const size_t last = hurtbox_ids.size() - 1;
	if (slot != last) {
		hurtbox_ids[slot] = hurtbox_ids[last];
		hurtbox_positions[slot] = hurtbox_positions[last];
		hurtbox_radii[slot] = hurtbox_radii[last];
		hurtbox_heights[slot] = hurtbox_heights[last];
		hurtbox_layers[slot] = hurtbox_layers[last];
		hurtbox_slots[hurtbox_ids[slot]] = slot;
	}
	hurtbox_ids.pop_back();
	hurtbox_positions.pop_back();
	hurtbox_radii.pop_back();
	hurtbox_heights.pop_back();
	hurtbox_layers.pop_back();
	hurtbox_slots.erase(id);
	for (auto &entry : hitboxes) entry.second.hit_ids.erase(id);
}

void HitManager::configure_hitbox(int32_t id, StringName shape, Vector3 size, int32_t linger_ticks, PackedFloat32Array decay_curve) {
	if (hitboxes.find(id) == hitboxes.end() && hitboxes.size() >= MAX_HITBOXES) return;
	Hitbox &hitbox = hitboxes[id];
	if (!shape_is(shape, SHAPE_SPHERE) && !shape_is(shape, SHAPE_CAPSULE) && !shape_is(shape, SHAPE_BOX) && !shape_is(shape, SHAPE_CONE) && !shape_is(shape, SHAPE_RING)) shape = StringName(String(SHAPE_SPHERE));
	hitbox.shape = shape_is(shape, SHAPE_CAPSULE) ? CAPSULE : shape_is(shape, SHAPE_BOX) ? BOX : shape_is(shape, SHAPE_CONE) ? CONE : shape_is(shape, SHAPE_RING) ? RING : SPHERE;
	hitbox.size = Vector3(std::max(0.0f, size.x), std::max(0.0f, size.y), std::max(0.0f, size.z));
	hitbox.linger_ticks = std::clamp(linger_ticks, 0, 256);
	hitbox.decay_curve.clear();
	const int32_t decay_samples = std::min<int32_t>(decay_curve.size(), 257);
	hitbox.decay_curve.reserve(decay_samples);
	for (int32_t i = 0; i < decay_samples; ++i) hitbox.decay_curve.push_back(std::clamp(decay_curve[i], 0.0f, 1.0f));
	while (static_cast<int32_t>(hitbox.trail.size()) > hitbox.linger_ticks) hitbox.trail.pop_back();
}

void HitManager::unregister_hitbox(int32_t id) {
	hitboxes.erase(id);
}

void HitManager::set_hitbox_mask(int32_t id, int64_t mask) {
	auto found = hitboxes.find(id);
	if (found != hitboxes.end()) found->second.collision_mask = static_cast<uint32_t>(mask);
}

void HitManager::activate_hitbox(int32_t id, bool active) {
	auto found = hitboxes.find(id);
	if (found == hitboxes.end()) return;
	Hitbox &hitbox = found->second;
	if (active && !hitbox.active) {
		hitbox.trail.clear();
		hitbox.previous_transform = hitbox.transform;
		hitbox.has_previous = false;
	}
	hitbox.active = active;
}

void HitManager::set_hitbox_transform(int32_t id, Transform3D transform) {
	auto found = hitboxes.find(id);
	if (found == hitboxes.end()) return;
	// All profiles use world dimensions. Canonicalize once on submission, not
	// again for every target and every conservative-advancement iteration.
	transform.basis.orthonormalize();
	Hitbox &hitbox = found->second;
	if (hitbox.transform != transform) {
		hitbox.previous_transform = hitbox.transform;
		hitbox.has_previous = true;
	}
	hitbox.transform = transform;
}

void HitManager::refresh(int32_t id) {
	auto found = hitboxes.find(id);
	if (found != hitboxes.end()) found->second.hit_ids.clear();
}

void HitManager::discard_hitbox_trails(int32_t id) {
	auto found = hitboxes.find(id);
	if (found == hitboxes.end()) return;
	found->second.trail.clear();
	found->second.previous_transform = found->second.transform;
	found->second.has_previous = false;
}

static double closest_point_parameter_on_segment(const Vector3 &point, const Vector3 &start, const Vector3 &end) {
	const Vector3 segment = end - start;
	const double length_squared = segment.length_squared();
	if (length_squared <= 0.000001) return 0.0;
	return std::clamp((point - start).dot(segment) / length_squared, 0.0, 1.0);
}

static Vector3 closest_point_on_segment(const Vector3 &point, const Vector3 &start, const Vector3 &end) {
	return start + (end - start) * closest_point_parameter_on_segment(point, start, end);
}

static double segment_segment_distance_squared(const Vector3 &p1, const Vector3 &q1, const Vector3 &p2, const Vector3 &q2, Vector3 *closest_first = nullptr, Vector3 *closest_second = nullptr) {
	const Vector3 d1 = q1 - p1;
	const Vector3 d2 = q2 - p2;
	const Vector3 r = p1 - p2;
	const double a = d1.dot(d1);
	const double e = d2.dot(d2);
	const double f = d2.dot(r);
	double s = 0.0;
	double t = 0.0;
	if (a <= 0.000001 && e <= 0.000001) {
		if (closest_first != nullptr) *closest_first = p1;
		if (closest_second != nullptr) *closest_second = p2;
		return p1.distance_squared_to(p2);
	} else if (a <= 0.000001) {
		t = std::clamp(f / e, 0.0, 1.0);
	} else {
		const double c = d1.dot(r);
		if (e <= 0.000001) {
			s = std::clamp(-c / a, 0.0, 1.0);
		} else {
			const double b = d1.dot(d2);
			const double denominator = a * e - b * b;
			if (denominator != 0.0) s = std::clamp((b * f - c * e) / denominator, 0.0, 1.0);
			t = (b * s + f) / e;
			if (t < 0.0) {
			t = 0.0;
			s = std::clamp(-c / a, 0.0, 1.0);
			} else if (t > 1.0) {
				t = 1.0;
				s = std::clamp((b - c) / a, 0.0, 1.0);
			}
		}
	}
	const Vector3 c1 = p1 + d1 * s;
	const Vector3 c2 = p2 + d2 * t;
	if (closest_first != nullptr) *closest_first = c1;
	if (closest_second != nullptr) *closest_second = c2;
	return c1.distance_squared_to(c2);
}

static Vector3 rounded_contact_point(const Vector3 &first_center, double first_radius, const Vector3 &second_axis_point, double second_radius) {
	const Vector3 delta = second_axis_point - first_center;
	const double distance = delta.length();
	const Vector3 normal = distance > 0.000001 ? delta / distance : Vector3(0.0, 1.0, 0.0);
	const Vector3 first_surface = first_center + normal * first_radius;
	const Vector3 second_surface = second_axis_point - normal * second_radius;
	return (first_surface + second_surface) * 0.5;
}

static void hurtbox_segment(const HitManager::Hurtbox &hurtbox, Vector3 &start, Vector3 &end) {
	const Vector3 center = hurtbox.position + Vector3(0.0, hurtbox.height * 0.5, 0.0);
	const double half_segment = std::max(0.0, hurtbox.height * 0.5 - hurtbox.radius);
	start = center - Vector3(0.0, half_segment, 0.0);
	end = center + Vector3(0.0, half_segment, 0.0);
}

static double segment_box_distance_squared(const Vector3 &start, const Vector3 &end, const Vector3 &half, Vector3 &contact) {
	const Vector3 direction = end - start;
	std::vector<double> breaks = {0.0, 1.0};
	for (int axis = 0; axis < 3; ++axis) {
		if (std::abs(direction[axis]) < 0.0000001) continue;
		for (double boundary : {-static_cast<double>(half[axis]), static_cast<double>(half[axis])}) {
			const double t = (boundary - start[axis]) / direction[axis];
			if (t > 0.0 && t < 1.0) breaks.push_back(t);
		}
	}
	std::sort(breaks.begin(), breaks.end());
	double best = INFINITY;
	auto evaluate = [&](double t) {
		const Vector3 point = start + direction * t;
		const Vector3 nearest(std::clamp(point.x, -half.x, half.x), std::clamp(point.y, -half.y, half.y), std::clamp(point.z, -half.z, half.z));
		const double distance = point.distance_squared_to(nearest);
		if (distance < best) { best = distance; contact = nearest; }
	};
	for (double t : breaks) evaluate(t);
	for (size_t interval = 1; interval < breaks.size(); ++interval) {
		const double lower = breaks[interval - 1];
		const double upper = breaks[interval];
		const Vector3 midpoint = start + direction * ((lower + upper) * 0.5);
		double numerator = 0.0;
		double denominator = 0.0;
		for (int axis = 0; axis < 3; ++axis) {
			if (midpoint[axis] >= -half[axis] && midpoint[axis] <= half[axis]) continue;
			const double boundary = midpoint[axis] < -half[axis] ? -half[axis] : half[axis];
			numerator += direction[axis] * (start[axis] - boundary);
			denominator += static_cast<double>(direction[axis]) * direction[axis];
		}
		evaluate(denominator > 0.0 ? std::clamp(-numerator / denominator, lower, upper) : (lower + upper) * 0.5);
	}
	return best;
}

static Vector3 closest_point_in_cone(const Vector3 &point, double length, double tangent) {
	const double depth = -point.z;
	const double radial = std::sqrt(point.x * point.x + point.y * point.y);
	const double base_radius = length * tangent;
	if (depth >= 0.0 && depth <= length && radial <= depth * tangent) return point;
	const Vector3 section(depth, radial, 0.0);
	const Vector3 apex;
	const Vector3 base_axis(length, 0.0, 0.0);
	const Vector3 base_rim(length, base_radius, 0.0);
	Vector3 closest = closest_point_on_segment(section, apex, base_rim);
	for (const Vector3 &candidate : {closest_point_on_segment(section, apex, base_axis), closest_point_on_segment(section, base_axis, base_rim)}) {
		if (section.distance_squared_to(candidate) < section.distance_squared_to(closest)) closest = candidate;
	}
	const double factor = radial > 0.0000001 ? closest.y / radial : 0.0;
	return Vector3(point.x * factor, point.y * factor, -closest.x);
}

static Vector3 closest_point_in_ring(const Vector3 &point, double inner, double outer, double half_height) {
	const double radial = std::sqrt(point.x * point.x + point.z * point.z);
	const double nearest_radius = std::clamp(radial, inner, outer);
	const double y = std::clamp(static_cast<double>(point.y), -half_height, half_height);
	if (radial < 0.0000001) return Vector3(nearest_radius, y, 0.0);
	return Vector3(point.x * nearest_radius / radial, y, point.z * nearest_radius / radial);
}

static double segment_ring_distance_squared(const Vector3 &start, const Vector3 &end, double inner, double outer, double half_height, Vector3 &contact) {
	const Vector3 direction = end - start;
	const double a = static_cast<double>(direction.x) * direction.x + static_cast<double>(direction.z) * direction.z;
	const double b = 2.0 * (static_cast<double>(start.x) * direction.x + static_cast<double>(start.z) * direction.z);
	const double c = static_cast<double>(start.x) * start.x + static_cast<double>(start.z) * start.z;
	std::vector<double> breaks = {0.0, 1.0};
	auto add_break = [&](double t) { if (t > 0.0 && t < 1.0) breaks.push_back(t); };
	auto add_radius_breaks = [&](double radius) {
		if (a <= 0.000000000001) return;
		const double discriminant = b * b - 4.0 * a * (c - radius * radius);
		if (discriminant < 0.0) return;
		const double root = std::sqrt(discriminant);
		add_break((-b - root) / (2.0 * a));
		add_break((-b + root) / (2.0 * a));
	};
	if (std::abs(direction.y) > 0.0000001) {
		add_break((-half_height - start.y) / direction.y);
		add_break((half_height - start.y) / direction.y);
	}
	add_radius_breaks(inner);
	add_radius_breaks(outer);
	if (a > 0.000000000001) {
		add_break(-b / (2.0 * a));
		const double perpendicular_squared = std::max(0.0, c - b * b / (4.0 * a));
		// Split where the inner-hole squared-distance derivative changes monotonicity,
		// for each vertical region (inside the slab or outside it).
		for (double vertical_curvature : {0.0, static_cast<double>(direction.y) * direction.y}) {
			add_radius_breaks(std::cbrt(inner * a * perpendicular_squared / (a + vertical_curvature)));
		}
	}
	std::sort(breaks.begin(), breaks.end());
	breaks.erase(std::unique(breaks.begin(), breaks.end()), breaks.end());
	double best = INFINITY;
	auto evaluate = [&](double t) {
		const Vector3 point = start + direction * t;
		const Vector3 nearest = closest_point_in_ring(point, inner, outer, half_height);
		const double distance = point.distance_squared_to(nearest);
		if (distance < best) { best = distance; contact = nearest; }
	};
	auto derivative = [&](double t) {
		const double x = start.x + direction.x * t;
		const double y = start.y + direction.y * t;
		const double z = start.z + direction.z * t;
		const double radial = std::sqrt(x * x + z * z);
		const double radial_term = radial > 0.000000000001 ? (radial - std::clamp(radial, inner, outer)) * (x * direction.x + z * direction.z) / radial : 0.0;
		return radial_term + (y - std::clamp(y, -half_height, half_height)) * direction.y;
	};
	for (double t : breaks) evaluate(t);
	for (size_t index = 1; index < breaks.size(); ++index) {
		double lower = breaks[index - 1];
		double upper = breaks[index];
		const double inset = (upper - lower) * 0.000001;
		double lower_derivative = derivative(lower + inset);
		const double upper_derivative = derivative(upper - inset);
		if (lower_derivative * upper_derivative >= 0.0) continue;
		for (int iteration = 0; iteration < 40; ++iteration) {
			const double middle = (lower + upper) * 0.5;
			const double middle_derivative = derivative(middle);
			if ((middle_derivative < 0.0) == (lower_derivative < 0.0)) {
				lower = middle;
				lower_derivative = middle_derivative;
			} else upper = middle;
		}
		evaluate((lower + upper) * 0.5);
	}
	return best;
}

static double profile_separation(const HitManager::Hitbox &hitbox, const Transform3D &transform, const HitManager::Hurtbox &hurtbox, Vector3 &contact) {
	Vector3 hurt_start;
	Vector3 hurt_end;
	hurtbox_segment(hurtbox, hurt_start, hurt_end);
	const Vector3 center = (hurt_start + hurt_end) * 0.5;
	const double hurt_radius = hurtbox.radius;
	const double radius = hitbox.size.x;
	if (hitbox.shape == HitManager::SPHERE) {
		const Vector3 closest = closest_point_on_segment(transform.origin, hurt_start, hurt_end);
		contact = rounded_contact_point(transform.origin, radius, closest, hurt_radius);
		return transform.origin.distance_to(closest) - radius - hurt_radius;
	}
	if (hitbox.shape == HitManager::CAPSULE) {
		const Vector3 axis = transform.basis.get_column(2).normalized() * hitbox.size.z * 0.5;
		const Vector3 start = transform.origin - axis;
		const Vector3 end = transform.origin + axis;
		contact = closest_point_on_segment(center, start, end);
		return std::sqrt(segment_segment_distance_squared(start, end, hurt_start, hurt_end)) - radius - hurt_radius;
	}
	const Transform3D &rigid = transform;
	const Basis inverse_rotation = rigid.basis.transposed();
	const Vector3 local_start = inverse_rotation.xform(hurt_start - rigid.origin);
	const Vector3 local_end = inverse_rotation.xform(hurt_end - rigid.origin);
	if (hitbox.shape == HitManager::BOX) {
		const Vector3 half = hitbox.size * 0.5;
		Vector3 local_contact;
		const double distance_squared = segment_box_distance_squared(local_start, local_end, half, local_contact);
		contact = rigid.xform(local_contact);
		return std::sqrt(distance_squared) - hurt_radius;
	}
	if (hitbox.shape == HitManager::CONE) {
		const double angle = std::clamp(static_cast<double>(hitbox.size.x), 0.0, 89.0);
		const double length = hitbox.size.z;
		const double tangent = std::tan(Math::deg_to_rad(angle));
		const Vector3 axis = local_end - local_start;
		if (axis.z == 0.0) {
			// At a fixed cone depth, distance is nondecreasing in radial distance.
			// Horizontal weapon cones against vertical capsules therefore need
			// only the capsule point nearest the cone axis, not a numerical search.
			const double radial_length_squared = static_cast<double>(axis.x) * axis.x + static_cast<double>(axis.y) * axis.y;
			const double t = radial_length_squared > 0.0 ? std::clamp(-(static_cast<double>(local_start.x) * axis.x + static_cast<double>(local_start.y) * axis.y) / radial_length_squared, 0.0, 1.0) : 0.0;
			const Vector3 point = local_start + axis * t;
			const Vector3 nearest = closest_point_in_cone(point, length, tangent);
			contact = rigid.xform(nearest);
			return point.distance_to(nearest) - hurt_radius;
		}
		// Squared distance to a convex cone is convex and differentiable along
		// the capsule centerline. An outward endpoint derivative proves that
		// endpoint is the global minimum; no binary search is needed. A sampled
		// centerline point already within the capsule radius proves contact too.
		const auto gradient = [&axis](const Vector3 &offset) {
			return static_cast<double>(axis.x) * offset.x + static_cast<double>(axis.y) * offset.y + static_cast<double>(axis.z) * offset.z;
		};
		const Vector3 start_nearest = closest_point_in_cone(local_start, length, tangent);
		const Vector3 start_offset = local_start - start_nearest;
		const double radius_squared = hurt_radius * hurt_radius;
		if (start_offset.length_squared() <= radius_squared || gradient(start_offset) >= 0.0) {
			contact = rigid.xform(start_nearest);
			return start_offset.length() - hurt_radius;
		}
		const Vector3 end_nearest = closest_point_in_cone(local_end, length, tangent);
		const Vector3 end_offset = local_end - end_nearest;
		if (end_offset.length_squared() <= radius_squared || gradient(end_offset) <= 0.0) {
			contact = rigid.xform(end_nearest);
			return end_offset.length() - hurt_radius;
		}
		const Vector3 midpoint = (local_start + local_end) * 0.5;
		const Vector3 middle_nearest = closest_point_in_cone(midpoint, length, tangent);
		const Vector3 middle_offset = midpoint - middle_nearest;
		if (middle_offset.length_squared() <= radius_squared) {
			contact = rigid.xform(middle_nearest);
			return middle_offset.length() - hurt_radius;
		}
		double lower = 0.0;
		double upper = 1.0;
		if (gradient(middle_offset) < 0.0) lower = 0.5;
		else upper = 0.5;
		for (int iteration = 1; iteration < 32; ++iteration) {
			const double t = (lower + upper) * 0.5;
			const Vector3 point = local_start + axis * t;
			const Vector3 nearest = closest_point_in_cone(point, length, tangent);
			if (gradient(point - nearest) < 0.0) lower = t;
			else upper = t;
		}
		double best = INFINITY;
		Vector3 nearest;
		for (double t : {0.0, 1.0, (lower + upper) * 0.5}) {
			const Vector3 point = local_start + axis * t;
			const Vector3 candidate = closest_point_in_cone(point, length, tangent);
			const double distance = point.distance_squared_to(candidate);
			if (distance < best) { best = distance; nearest = candidate; }
		}
		contact = rigid.xform(nearest);
		return std::sqrt(best) - hurt_radius;
	}
	if (hitbox.shape == HitManager::RING) {
		const double ring_radius = hitbox.size.x;
		const double thickness = hitbox.size.y;
		const double half_height = hitbox.size.z * 0.5;
		Vector3 nearest;
		const double distance_squared = segment_ring_distance_squared(local_start, local_end, std::max(0.0, ring_radius - thickness), ring_radius + thickness, half_height, nearest);
		contact = rigid.xform(nearest);
		return std::sqrt(distance_squared) - hurt_radius;
	}
	return INFINITY;
}

static double profile_broad_radius(const HitManager::Hitbox &hitbox) {
	if (hitbox.shape == HitManager::BOX) return hitbox.size.length() * 0.5;
	if (hitbox.shape == HitManager::CONE) return hitbox.size.z / std::cos(Math::deg_to_rad(std::clamp(static_cast<double>(hitbox.size.x), 0.0, 89.0)));
	if (hitbox.shape == HitManager::RING) {
		const double outer = hitbox.size.x + hitbox.size.y;
		const double half_height = hitbox.size.z * 0.5;
		return std::sqrt(outer * outer + half_height * half_height);
	}
	return hitbox.size.x + (hitbox.shape == HitManager::CAPSULE ? hitbox.size.z * 0.5 : 0.0);
}

static Transform3D interpolate_rigid_pose(const Transform3D &start, const Transform3D &end, const Quaternion &start_rotation, const Quaternion &end_rotation, double t) {
	// Compute translation before narrowing to real_t, avoiding loss of small
	// contact intervals when endpoints are far apart but the contact is near zero.
	Vector3 origin;
	for (int axis = 0; axis < 3; ++axis) origin[axis] = static_cast<double>(start.origin[axis]) + (static_cast<double>(end.origin[axis]) - start.origin[axis]) * t;
	return Transform3D(Basis(start_rotation.slerp(end_rotation, t)), origin);
}

static bool sweep_intersects(const HitManager::Hitbox &hitbox, const HitManager::TrailPose &pose, const HitManager::Hurtbox &hurtbox, Vector3 &contact, Transform3D &contact_transform, bool &exhausted, double profile_radius) {
	const Quaternion &start_rotation = pose.start_rotation;
	const Quaternion &end_rotation = pose.end_rotation;
	const double angle = pose.rotation_angle;
	const double motion_bound = pose.translation_distance + angle * profile_radius;
	constexpr double tolerance = 0.00001;
	if (angle > 0.000001) {
		// Rotation preserves each point's projection on its world rotation axis.
		// This bound rejects near misses above/below a thin rotating volume.
		const Quaternion delta = end_rotation * start_rotation.inverse();
		const Vector3 rotation_axis = Vector3(delta.x, delta.y, delta.z).normalized();
		const Vector3 local_axis = Basis(start_rotation).transposed().xform(rotation_axis);
		double minimum = 0.0;
		double maximum = 0.0;
		if (hitbox.shape == HitManager::SPHERE) maximum = hitbox.size.x;
		else if (hitbox.shape == HitManager::BOX) maximum = local_axis.abs().dot(hitbox.size * 0.5);
		else if (hitbox.shape == HitManager::CAPSULE) maximum = hitbox.size.x + std::abs(local_axis.z) * hitbox.size.z * 0.5;
		else if (hitbox.shape == HitManager::CONE) {
			const double radial = hitbox.size.z * std::tan(Math::deg_to_rad(std::clamp(static_cast<double>(hitbox.size.x), 0.0, 89.0))) * std::sqrt(local_axis.x * local_axis.x + local_axis.y * local_axis.y);
			const double base = -local_axis.z * hitbox.size.z;
			minimum = std::min(0.0, base - radial);
			maximum = std::max(0.0, base + radial);
		} else if (hitbox.shape == HitManager::RING) maximum = (hitbox.size.x + hitbox.size.y) * std::sqrt(local_axis.x * local_axis.x + local_axis.z * local_axis.z) + hitbox.size.z * 0.5 * std::abs(local_axis.y);
		if (hitbox.shape != HitManager::CONE) minimum = -maximum;
		const double start_projection = pose.previous_transform.origin.dot(rotation_axis);
		const double end_projection = pose.transform.origin.dot(rotation_axis);
		minimum += std::min(start_projection, end_projection);
		maximum += std::max(start_projection, end_projection);
		Vector3 hurt_start;
		Vector3 hurt_end;
		hurtbox_segment(hurtbox, hurt_start, hurt_end);
		const double a = hurt_start.dot(rotation_axis);
		const double b = hurt_end.dot(rotation_axis);
		if (std::min(a, b) - hurtbox.radius > maximum + tolerance || std::max(a, b) + hurtbox.radius < minimum - tolerance) return false;
	}
	double t = 0.0;
	for (int iteration = 0; iteration < 1024; ++iteration) {
		if (iteration == 32 && angle == 0.0 && hitbox.shape != HitManager::RING) {
			// Under pure translation, distance between these convex volumes is
			// convex in time. Minimize it to avoid tiny advancement steps on a
			// long parallel near miss.
			double lower = t;
			double upper = 1.0;
			Vector3 scratch;
			for (int search = 0; search < 64; ++search) {
				const double first = lower + (upper - lower) / 3.0;
				const double second = upper - (upper - lower) / 3.0;
				const double a = profile_separation(hitbox, interpolate_rigid_pose(pose.previous_transform, pose.transform, start_rotation, end_rotation, first), hurtbox, scratch);
				const double b = profile_separation(hitbox, interpolate_rigid_pose(pose.previous_transform, pose.transform, start_rotation, end_rotation, second), hurtbox, scratch);
				if (a < b) upper = second;
				else lower = first;
			}
			const double contact_t = (lower + upper) * 0.5;
			contact_transform = interpolate_rigid_pose(pose.previous_transform, pose.transform, start_rotation, end_rotation, contact_t);
			return profile_separation(hitbox, contact_transform, hurtbox, contact) <= tolerance;
		}
		const Transform3D transform = interpolate_rigid_pose(pose.previous_transform, pose.transform, start_rotation, end_rotation, t);
		const double separation = profile_separation(hitbox, transform, hurtbox, contact);
		if (separation <= tolerance) {
			contact_transform = transform;
			return true;
		}
		if (motion_bound <= tolerance || separation > motion_bound * (1.0 - t) + tolerance) return false;
		const double next_t = t + separation / motion_bound;
		if (next_t >= 1.0) {
			contact_transform = pose.transform;
			return profile_separation(hitbox, contact_transform, hurtbox, contact) <= tolerance;
		}
		if (next_t <= t) break;
		t = next_t;
	}
	exhausted = true;
	return false;
}

static float potency_at_age(const HitManager::Hitbox &hitbox, double age) {
	if (!hitbox.decay_curve.empty()) {
		const double normalized = hitbox.linger_ticks > 0 ? std::clamp(static_cast<double>(age) / hitbox.linger_ticks, 0.0, 1.0) : 0.0;
		const double sample = normalized * (hitbox.decay_curve.size() - 1);
		const size_t lower = static_cast<size_t>(sample);
		const size_t upper = std::min(lower + 1, hitbox.decay_curve.size() - 1);
		const double fraction = sample - lower;
		return static_cast<float>(hitbox.decay_curve[lower] * (1.0 - fraction) + hitbox.decay_curve[upper] * fraction);
	}
	const double normalized = hitbox.linger_ticks > 0 ? static_cast<double>(age) / hitbox.linger_ticks : 0.0;
	return static_cast<float>(std::max(0.0, 1.0 - 0.7 * normalized));
}

Dictionary HitManager::get_debug_snapshot() const {
	// Opt-in diagnostics only. Reading a snapshot cannot age history, refresh
	// hit sets, or alter the registry. No allocation is added to step().
	Array debug_hurtboxes;
	for (size_t slot = 0; slot < hurtbox_ids.size(); ++slot) {
		Dictionary entry;
		entry["id"] = hurtbox_ids[slot];
		entry["position"] = hurtbox_positions[slot];
		entry["radius"] = hurtbox_radii[slot];
		entry["height"] = hurtbox_heights[slot];
		entry["layer"] = hurtbox_layers[slot];
		debug_hurtboxes.push_back(entry);
	}
	Array debug_hitboxes;
	const char *shape_names[] = {SHAPE_SPHERE, SHAPE_CAPSULE, SHAPE_BOX, SHAPE_CONE, SHAPE_RING};
	for (const auto &pair : hitboxes) {
		const Hitbox &hitbox = pair.second;
		if (hitbox.trail.empty()) continue;
		Dictionary entry;
		entry["id"] = pair.first;
		entry["shape"] = StringName(String(shape_names[hitbox.shape]));
		entry["size"] = hitbox.size;
		entry["active"] = hitbox.active;
		entry["mask"] = static_cast<int64_t>(hitbox.collision_mask);
		Array poses;
		for (const TrailPose &pose : hitbox.trail) {
			Dictionary sample;
			sample["transform"] = pose.transform;
			sample["previous_transform"] = pose.previous_transform;
			sample["swept"] = pose.swept;
			sample["age"] = pose.age;
			sample["potency"] = potency_at_age(hitbox, pose.age);
			poses.push_back(sample);
		}
		entry["poses"] = poses;
		debug_hitboxes.push_back(entry);
	}
	Dictionary result;
	result["hurtboxes"] = debug_hurtboxes;
	result["hitboxes"] = debug_hitboxes;
	return result;
}

Array HitManager::step() {
	return step_internal(nullptr, false);
}

Array HitManager::step_with_ages(PackedInt32Array ids, PackedFloat32Array age_tick_deltas) {
	if (ids.size() != age_tick_deltas.size()) {
		UtilityFunctions::push_warning("HitManager.step_with_ages requires matching ID and age-delta lengths");
		return Array();
	}
	std::unordered_map<int32_t, double> age_deltas;
	age_deltas.reserve(ids.size());
	for (int64_t index = 0; index < ids.size(); ++index) {
		const int32_t id = ids[index];
		const double delta = age_tick_deltas[index];
		if (id < 0 || hitboxes.find(id) == hitboxes.end() || !std::isfinite(delta) || delta < 0.0 || age_deltas.find(id) != age_deltas.end()) {
			UtilityFunctions::push_warning("HitManager.step_with_ages received an unknown/duplicate ID or invalid age delta");
			return Array();
		}
		age_deltas.emplace(id, delta);
	}
	return step_internal(&age_deltas, true);
}

Array HitManager::step_internal(const std::unordered_map<int32_t, double> *age_deltas, bool deduplicate_stationary) {
	Array contacts;
	for (auto &hitbox_entry : hitboxes) {
		Hitbox &hitbox = hitbox_entry.second;
		if (!hitbox.active && hitbox.trail.empty()) continue;
		double age_delta = 1.0;
		if (age_deltas != nullptr) {
			auto age_entry = age_deltas->find(hitbox_entry.first);
			if (age_entry != age_deltas->end()) age_delta = age_entry->second;
		}
		for (TrailPose &pose : hitbox.trail) pose.age += age_delta;
		while (!hitbox.trail.empty() && hitbox.trail.back().age > hitbox.linger_ticks) hitbox.trail.pop_back();
		if (hitbox.active) {
			TrailPose pose;
			pose.transform = hitbox.transform;
			pose.previous_transform = hitbox.previous_transform;
			pose.swept = hitbox.has_previous;
			if (pose.swept) {
				pose.start_rotation = pose.previous_transform.basis.get_rotation_quaternion();
				pose.end_rotation = pose.transform.basis.get_rotation_quaternion();
				pose.rotation_angle = pose.start_rotation == pose.end_rotation ? 0.0 : 2.0 * std::acos(std::clamp(std::abs(static_cast<double>(pose.start_rotation.dot(pose.end_rotation))), 0.0, 1.0));
				pose.translation_distance = pose.previous_transform.origin.distance_to(pose.transform.origin);
			}
			const bool refresh_stationary_pose = deduplicate_stationary && !pose.swept && !hitbox.trail.empty()
					&& !hitbox.trail.front().swept && hitbox.trail.front().transform == pose.transform;
			if (refresh_stationary_pose) {
				hitbox.trail.front().age = 0.0;
			} else {
				hitbox.trail.push_front(pose);
			}
		}
		if (hitbox.trail.empty()) continue;
		if (hitbox.linger_ticks == 0) hitbox.trail.resize(1);
		Vector3 lower = hitbox.transform.origin;
		Vector3 upper = lower;
		for (const TrailPose &pose : hitbox.trail) {
			lower = lower.min(pose.transform.origin);
			upper = upper.max(pose.transform.origin);
			if (pose.swept) {
				lower = lower.min(pose.previous_transform.origin);
				upper = upper.max(pose.previous_transform.origin);
			}
		}
		if (hitbox.has_previous) {
			lower = lower.min(hitbox.previous_transform.origin);
			upper = upper.max(hitbox.previous_transform.origin);
		}
		const double bounds_radius = profile_broad_radius(hitbox);
		lower -= Vector3(bounds_radius, bounds_radius, bounds_radius);
		upper += Vector3(bounds_radius, bounds_radius, bounds_radius);
		for (size_t slot = 0; slot < hurtbox_ids.size(); ++slot) {
			const int32_t hurtbox_id = hurtbox_ids[slot];
			const Hurtbox hurtbox = hurtbox_at(slot);
			if ((hitbox.collision_mask & static_cast<uint32_t>(hurtbox.layer)) == 0) continue;
			if (hitbox.hit_ids.find(hurtbox_id) != hitbox.hit_ids.end()) continue;
			const Vector3 center = hurtbox.position + Vector3(0.0, hurtbox.height * 0.5, 0.0);
			const Vector3 half(hurtbox.radius, std::max(hurtbox.height * 0.5f, hurtbox.radius), hurtbox.radius);
			if (center.x + half.x < lower.x || center.x - half.x > upper.x || center.y + half.y < lower.y || center.y - half.y > upper.y || center.z + half.z < lower.z || center.z - half.z > upper.z) continue;
			bool struck = false;
			Vector3 contact_position;
			Transform3D contact_transform = Transform3D();
			Transform3D contact_previous_transform = Transform3D();
			bool contact_swept = false;
			int32_t contact_trail_age = 0;
			float potency = 0.0f;
			for (const TrailPose &pose : hitbox.trail) {
				if (hitbox.shape == SPHERE && pose.swept) {
					Vector3 start;
					Vector3 end;
					hurtbox_segment(hurtbox, start, end);
					const double radius = hitbox.size.x + hurtbox.radius;
					Vector3 closest_on_sweep;
					Vector3 closest_on_hurtbox;
					if (segment_segment_distance_squared(pose.previous_transform.origin, pose.transform.origin, start, end, &closest_on_sweep, &closest_on_hurtbox) <= radius * radius) {
						struck = true;
						const double contact_t = closest_point_parameter_on_segment(closest_on_sweep, pose.previous_transform.origin, pose.transform.origin);
						contact_transform = interpolate_rigid_pose(pose.previous_transform, pose.transform, pose.start_rotation, pose.end_rotation, contact_t);
						contact_position = rounded_contact_point(closest_on_sweep, hitbox.size.x, closest_on_hurtbox, hurtbox.radius);
						contact_previous_transform = pose.previous_transform;
						contact_swept = pose.swept;
						contact_trail_age = pose.age;
						potency = potency_at_age(hitbox, pose.age);
						break;
					}
					continue;
				}
				bool exhausted = false;
				if (pose.swept) {
					struck = sweep_intersects(hitbox, pose, hurtbox, contact_position, contact_transform, exhausted, bounds_radius);
				} else {
					contact_transform = pose.transform;
					struck = profile_separation(hitbox, contact_transform, hurtbox, contact_position) <= 0.0;
				}
				if (exhausted) {
					++sweep_exhaustions;
					UtilityFunctions::push_warning("HitManager continuous sweep exhausted its numerical iteration budget");
				}
				if (struck) {
					potency = potency_at_age(hitbox, pose.age);
					contact_previous_transform = pose.previous_transform;
					contact_swept = pose.swept;
					contact_trail_age = pose.age;
					break;
				}
			}
			if (!struck) continue;
			hitbox.hit_ids.insert(hurtbox_id);
			Dictionary contact;
			contact["hitbox_id"] = hitbox_entry.first;
			contact["hurtbox_id"] = hurtbox_id;
			contact["potency"] = potency;
			contact["position"] = contact_position;
			contact["transform"] = contact_transform;
			contact["previous_transform"] = contact_previous_transform;
			contact["swept"] = contact_swept;
			contact["trail_age"] = contact_trail_age;
			contacts.push_back(contact);
		}
		hitbox.previous_transform = hitbox.transform;
		hitbox.has_previous = false;
	}
	return contacts;
}

Dictionary HitManager::raycast(Vector3 origin, Vector3 direction, double distance, double cone_degrees, int64_t mask, int32_t preferred_id) {
	Dictionary result;
	if (direction.length_squared() < 0.000001 || distance <= 0.0) return result;
	const Vector3 aim = direction.normalized();
	const double minimum_dot = std::cos(Math::deg_to_rad(std::clamp(cone_degrees, 0.0, 180.0)));
	double closest_distance = std::max(0.0, distance);
	int32_t closest_id = -1;
	Vector3 closest_position;
	for (size_t slot = 0; slot < hurtbox_ids.size(); ++slot) {
		const int32_t id = hurtbox_ids[slot];
		const Hurtbox hurtbox = hurtbox_at(slot);
		if ((static_cast<uint32_t>(mask) & static_cast<uint32_t>(hurtbox.layer)) == 0) continue;
		const Vector3 center = hurtbox.position + Vector3(0.0, hurtbox.height * 0.5, 0.0);
		const Vector3 offset = center - origin;
		const double center_distance = offset.length();
		if (center_distance > distance) continue;
		if (id == preferred_id) {
			result["hurtbox_id"] = id;
			result["distance"] = center_distance;
			result["position"] = center;
			return result;
		}
		const double along = offset.dot(aim);
		if (along < 0.0 || center_distance > closest_distance) continue;
		const Vector3 point = origin + aim * along;
		if (cone_degrees > 0.0) {
			if (center_distance > 0.000001 && aim.dot(offset / center_distance) < minimum_dot) continue;
		} else {
			Vector3 start;
			Vector3 end;
			hurtbox_segment(hurtbox, start, end);
			if (segment_segment_distance_squared(origin, origin + aim * distance, start, end) > hurtbox.radius * hurtbox.radius) continue;
		}
		closest_distance = center_distance;
		closest_id = id;
		closest_position = cone_degrees > 0.0 ? center : point;
	}
	if (closest_id >= 0) {
		result["hurtbox_id"] = closest_id;
		result["distance"] = closest_distance;
		result["position"] = closest_position;
	}
	return result;
}
