USE ride_registry;

-- 1. List currently matchable drivers and their vehicles.
SELECT * FROM v_eligible_driver_vehicles ORDER BY dispatch_name, vehicle_type, driver_id;

-- 2. List pending requests with passenger and endpoint names.
SELECT rr.request_id, p.full_name AS passenger, rr.vehicle_type,
       pickup.node_name AS pickup, dropoff.node_name AS dropoff,
       rr.distance_estimate_km, rr.request_status
FROM ride_requests rr
JOIN passengers p ON p.passenger_id = rr.passenger_id
JOIN route_nodes pickup ON pickup.route_node_id = rr.pickup_node_id
JOIN route_nodes dropoff ON dropoff.route_node_id = rr.drop_node_id
WHERE rr.request_status = 'PENDING';

-- 3. Count requests by local dispatch zone and vehicle category.
SELECT dn.node_name AS dispatch_zone, rr.vehicle_type, COUNT(*) AS request_count
FROM ride_requests rr
JOIN dispatch_nodes dn ON dn.dispatch_node_id = rr.dispatch_node_id
GROUP BY dn.node_name, rr.vehicle_type
ORDER BY request_count DESC;

-- 4. Show the current verified/valid state of every vehicle's required documents.
SELECT d.full_name, v.registration_no, v.vehicle_type,
       reg.verification_status AS registration_status, reg.valid_until AS registration_expiry,
       ins.verification_status AS insurance_status, ins.valid_until AS insurance_expiry
FROM drivers d
JOIN vehicles v ON v.driver_id = d.driver_id
LEFT JOIN vehicle_documents reg ON reg.vehicle_id = v.vehicle_id AND reg.document_type = 'REGISTRATION'
LEFT JOIN vehicle_documents ins ON ins.vehicle_id = v.vehicle_id AND ins.document_type = 'INSURANCE';

-- 5. Match a pending request (try a seed request ID that is still pending).
-- CALL sp_match_ride(1);

-- 6. Full trip registry with passenger, driver, route, status, and fare.
SELECT * FROM v_trip_registry ORDER BY assigned_at DESC;

-- 7. Average driver rating and review count (includes drivers without reviews).
SELECT * FROM v_driver_review_aggregates ORDER BY average_rating DESC, review_count DESC;

-- 8. Total completed fare by vehicle category.
SELECT vehicle_type, COUNT(*) AS completed_trip_count,
       ROUND(SUM(total_fare), 2) AS completed_fare_total,
       ROUND(AVG(total_fare), 2) AS average_fare
FROM v_trip_registry
WHERE trip_status = 'COMPLETED'
GROUP BY vehicle_type;

-- 9. Demand-to-eligible-driver ratio by zone and vehicle class.
SELECT q.dispatch_node_id, dn.node_name AS dispatch_zone, q.vehicle_type,
       q.pending_requests, COALESCE(s.eligible_drivers, 0) AS eligible_drivers,
       ROUND(q.pending_requests / NULLIF(s.eligible_drivers, 0), 2) AS demand_supply_ratio
FROM (
  SELECT dispatch_node_id, vehicle_type, COUNT(*) AS pending_requests
  FROM ride_requests WHERE request_status = 'PENDING'
  GROUP BY dispatch_node_id, vehicle_type
) q
JOIN dispatch_nodes dn ON dn.dispatch_node_id = q.dispatch_node_id
LEFT JOIN (
  SELECT dispatch_node_id, vehicle_type, COUNT(*) AS eligible_drivers
  FROM v_eligible_driver_vehicles GROUP BY dispatch_node_id, vehicle_type
) s ON s.dispatch_node_id = q.dispatch_node_id AND s.vehicle_type = q.vehicle_type;

-- 10. List trips with their ordered route stops.
SELECT tr.trip_id, tr.sequence_no, rn.node_name, rn.locality, tr.reached_at
FROM trip_route_nodes tr
JOIN route_nodes rn ON rn.route_node_id = tr.route_node_id
ORDER BY tr.trip_id, tr.sequence_no;

-- 11. Show document records expiring in the next 30 days.
SELECT v.registration_no, d.full_name AS driver_name, vd.document_type,
       vd.valid_until, vd.verification_status
FROM vehicle_documents vd
JOIN vehicles v ON v.vehicle_id = vd.vehicle_id
JOIN drivers d ON d.driver_id = v.driver_id
WHERE vd.valid_until BETWEEN CURRENT_DATE() AND DATE_ADD(CURRENT_DATE(), INTERVAL 30 DAY)
ORDER BY vd.valid_until;

-- 12. Find completed trips that have not received a review.
SELECT t.trip_id, p.full_name AS passenger_name, d.full_name AS driver_name
FROM trips t
JOIN ride_requests rr ON rr.request_id = t.request_id
JOIN passengers p ON p.passenger_id = rr.passenger_id
JOIN drivers d ON d.driver_id = t.driver_id
LEFT JOIN reviews rv ON rv.trip_id = t.trip_id
WHERE t.trip_status = 'COMPLETED' AND rv.review_id IS NULL;

-- 13. Fare breakdown: pricing components saved at match time.
SELECT trip_id, distance_km, base_fare, per_km_rate, surge_multiplier,
       ROUND((base_fare + per_km_rate * distance_km) * surge_multiplier, 2) AS recomputed_fare,
       total_fare AS stored_fare
FROM trips;

-- 14. Index review for matching/status lookups.
SHOW INDEX FROM ride_requests;
SHOW INDEX FROM drivers;
SHOW INDEX FROM trips;

-- 15. Inspect the current pricing rules.
SELECT vehicle_type, base_fare, per_km_rate, minimum_fare FROM pricing_rules ORDER BY vehicle_type;
