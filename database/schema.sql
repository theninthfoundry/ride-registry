-- Ride Registry DBMS PBL | MySQL 8+
-- Rebuilds the classroom demo database from scratch.
DROP DATABASE IF EXISTS ride_registry;
CREATE DATABASE ride_registry CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
USE ride_registry;

CREATE TABLE dispatch_nodes (
    dispatch_node_id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    node_name VARCHAR(80) NOT NULL,
    zone_code VARCHAR(20) NOT NULL UNIQUE,
    status ENUM('ACTIVE','PAUSED') NOT NULL DEFAULT 'ACTIVE',
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

CREATE TABLE route_nodes (
    route_node_id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    node_name VARCHAR(100) NOT NULL,
    locality VARCHAR(100) NOT NULL,
    latitude DECIMAL(9,6) NULL,
    longitude DECIMAL(9,6) NULL,
    dispatch_node_id BIGINT UNSIGNED NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_route_dispatch FOREIGN KEY (dispatch_node_id)
        REFERENCES dispatch_nodes(dispatch_node_id),
    CONSTRAINT uq_route_node_locality UNIQUE (node_name, locality)
) ENGINE=InnoDB;

CREATE TABLE passengers (
    passenger_id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    full_name VARCHAR(100) NOT NULL,
    phone VARCHAR(20) NOT NULL UNIQUE,
    email VARCHAR(160) NULL UNIQUE,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

CREATE TABLE drivers (
    driver_id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    full_name VARCHAR(100) NOT NULL,
    phone VARCHAR(20) NOT NULL UNIQUE,
    current_node_id BIGINT UNSIGNED NOT NULL,
    dispatch_node_id BIGINT UNSIGNED NOT NULL,
    driver_status ENUM('AVAILABLE','ON_TRIP','OFFLINE','SUSPENDED') NOT NULL DEFAULT 'OFFLINE',
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_driver_current_node FOREIGN KEY (current_node_id)
        REFERENCES route_nodes(route_node_id),
    CONSTRAINT fk_driver_dispatch FOREIGN KEY (dispatch_node_id)
        REFERENCES dispatch_nodes(dispatch_node_id),
    INDEX idx_driver_dispatch_status (dispatch_node_id, driver_status)
) ENGINE=InnoDB;

CREATE TABLE vehicles (
    vehicle_id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    driver_id BIGINT UNSIGNED NOT NULL UNIQUE,
    vehicle_type ENUM('BIKE','AUTO','CAB') NOT NULL,
    registration_no VARCHAR(30) NOT NULL UNIQUE,
    make_model VARCHAR(100) NOT NULL,
    capacity TINYINT UNSIGNED NOT NULL DEFAULT 3,
    vehicle_status ENUM('ACTIVE','INACTIVE') NOT NULL DEFAULT 'ACTIVE',
    CONSTRAINT fk_vehicle_driver FOREIGN KEY (driver_id) REFERENCES drivers(driver_id),
    CONSTRAINT chk_vehicle_capacity CHECK (capacity >= 1)
) ENGINE=InnoDB;

CREATE TABLE vehicle_documents (
    document_id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    vehicle_id BIGINT UNSIGNED NOT NULL,
    document_type ENUM('REGISTRATION','INSURANCE','PERMIT') NOT NULL,
    document_number VARCHAR(60) NOT NULL,
    valid_until DATE NOT NULL,
    verification_status ENUM('PENDING','VERIFIED','REJECTED') NOT NULL DEFAULT 'PENDING',
    verified_at DATETIME NULL,
    CONSTRAINT fk_document_vehicle FOREIGN KEY (vehicle_id) REFERENCES vehicles(vehicle_id) ON DELETE CASCADE,
    CONSTRAINT uq_vehicle_document_type UNIQUE (vehicle_id, document_type),
    INDEX idx_document_eligibility (document_type, verification_status, valid_until)
) ENGINE=InnoDB;

CREATE TABLE pricing_rules (
    vehicle_type ENUM('BIKE','AUTO','CAB') PRIMARY KEY,
    base_fare DECIMAL(8,2) NOT NULL,
    per_km_rate DECIMAL(8,2) NOT NULL,
    minimum_fare DECIMAL(8,2) NOT NULL DEFAULT 0.00,
    CONSTRAINT chk_pricing_values CHECK (base_fare >= 0 AND per_km_rate >= 0 AND minimum_fare >= 0)
) ENGINE=InnoDB;

CREATE TABLE ride_requests (
    request_id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    passenger_id BIGINT UNSIGNED NOT NULL,
    pickup_node_id BIGINT UNSIGNED NOT NULL,
    drop_node_id BIGINT UNSIGNED NOT NULL,
    dispatch_node_id BIGINT UNSIGNED NOT NULL,
    vehicle_type ENUM('BIKE','AUTO','CAB') NOT NULL,
    distance_estimate_km DECIMAL(7,2) NOT NULL,
    request_status ENUM('PENDING','MATCHED','COMPLETED','CANCELLED') NOT NULL DEFAULT 'PENDING',
    requested_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_request_passenger FOREIGN KEY (passenger_id) REFERENCES passengers(passenger_id),
    CONSTRAINT fk_request_pricing FOREIGN KEY (vehicle_type) REFERENCES pricing_rules(vehicle_type),
    CONSTRAINT fk_request_pickup FOREIGN KEY (pickup_node_id) REFERENCES route_nodes(route_node_id),
    CONSTRAINT fk_request_drop FOREIGN KEY (drop_node_id) REFERENCES route_nodes(route_node_id),
    CONSTRAINT fk_request_dispatch FOREIGN KEY (dispatch_node_id) REFERENCES dispatch_nodes(dispatch_node_id),
    CONSTRAINT chk_request_route CHECK (pickup_node_id <> drop_node_id),
    CONSTRAINT chk_request_distance CHECK (distance_estimate_km > 0),
    INDEX idx_request_match (dispatch_node_id, request_status, vehicle_type, requested_at)
) ENGINE=InnoDB;

CREATE TABLE trips (
    trip_id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    request_id BIGINT UNSIGNED NOT NULL UNIQUE,
    driver_id BIGINT UNSIGNED NOT NULL,
    vehicle_id BIGINT UNSIGNED NOT NULL,
    dispatch_node_id BIGINT UNSIGNED NOT NULL,
    trip_status ENUM('ASSIGNED','IN_PROGRESS','COMPLETED','CANCELLED') NOT NULL DEFAULT 'ASSIGNED',
    assigned_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    started_at DATETIME NULL,
    completed_at DATETIME NULL,
    distance_km DECIMAL(7,2) NOT NULL,
    base_fare DECIMAL(8,2) NOT NULL,
    per_km_rate DECIMAL(8,2) NOT NULL,
    surge_multiplier DECIMAL(4,2) NOT NULL DEFAULT 1.00,
    total_fare DECIMAL(10,2) NOT NULL,
    CONSTRAINT fk_trip_request FOREIGN KEY (request_id) REFERENCES ride_requests(request_id),
    CONSTRAINT fk_trip_driver FOREIGN KEY (driver_id) REFERENCES drivers(driver_id),
    CONSTRAINT fk_trip_vehicle FOREIGN KEY (vehicle_id) REFERENCES vehicles(vehicle_id),
    CONSTRAINT fk_trip_dispatch FOREIGN KEY (dispatch_node_id) REFERENCES dispatch_nodes(dispatch_node_id),
    CONSTRAINT chk_trip_distance CHECK (distance_km > 0),
    CONSTRAINT chk_trip_surge CHECK (surge_multiplier >= 1.00),
    INDEX idx_trip_status_time (trip_status, assigned_at),
    INDEX idx_trip_driver_status (driver_id, trip_status)
) ENGINE=InnoDB;

CREATE TABLE trip_route_nodes (
    trip_id BIGINT UNSIGNED NOT NULL,
    sequence_no SMALLINT UNSIGNED NOT NULL,
    route_node_id BIGINT UNSIGNED NOT NULL,
    reached_at DATETIME NULL,
    PRIMARY KEY (trip_id, sequence_no),
    CONSTRAINT fk_trip_route_trip FOREIGN KEY (trip_id) REFERENCES trips(trip_id) ON DELETE CASCADE,
    CONSTRAINT fk_trip_route_node FOREIGN KEY (route_node_id) REFERENCES route_nodes(route_node_id),
    CONSTRAINT chk_route_sequence CHECK (sequence_no >= 1)
) ENGINE=InnoDB;

CREATE TABLE reviews (
    review_id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    trip_id BIGINT UNSIGNED NOT NULL UNIQUE,
    rating TINYINT UNSIGNED NOT NULL,
    comment VARCHAR(500) NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_review_trip FOREIGN KEY (trip_id) REFERENCES trips(trip_id),
    CONSTRAINT chk_review_rating CHECK (rating BETWEEN 1 AND 5),
    INDEX idx_review_rating (rating)
) ENGINE=InnoDB;

-- Views keep repeated joins and aggregate calculations out of the UI.
CREATE VIEW v_eligible_driver_vehicles AS
SELECT d.driver_id, d.full_name AS driver_name, d.phone AS driver_phone,
       d.current_node_id, d.dispatch_node_id, dn.node_name AS dispatch_name,
       v.vehicle_id, v.vehicle_type, v.registration_no, v.make_model, v.capacity
FROM drivers d
JOIN vehicles v ON v.driver_id = d.driver_id
JOIN dispatch_nodes dn ON dn.dispatch_node_id = d.dispatch_node_id
WHERE d.driver_status = 'AVAILABLE'
  AND dn.status = 'ACTIVE'
  AND v.vehicle_status = 'ACTIVE'
  AND EXISTS (
      SELECT 1 FROM vehicle_documents vd
      WHERE vd.vehicle_id = v.vehicle_id AND vd.document_type = 'REGISTRATION'
        AND vd.verification_status = 'VERIFIED' AND vd.valid_until >= CURRENT_DATE()
  )
  AND EXISTS (
      SELECT 1 FROM vehicle_documents vd
      WHERE vd.vehicle_id = v.vehicle_id AND vd.document_type = 'INSURANCE'
        AND vd.verification_status = 'VERIFIED' AND vd.valid_until >= CURRENT_DATE()
  );

CREATE VIEW v_trip_registry AS
SELECT t.trip_id, t.trip_status, t.assigned_at, t.started_at, t.completed_at,
       t.distance_km, t.base_fare, t.per_km_rate, t.surge_multiplier, t.total_fare,
       p.full_name AS passenger_name, p.phone AS passenger_phone,
       d.driver_id, d.full_name AS driver_name,
       v.vehicle_type, v.registration_no,
       rp.node_name AS pickup_name, rd.node_name AS drop_name,
       dn.node_name AS dispatch_name, rr.request_id, rr.request_status
FROM trips t
JOIN ride_requests rr ON rr.request_id = t.request_id
JOIN passengers p ON p.passenger_id = rr.passenger_id
JOIN drivers d ON d.driver_id = t.driver_id
JOIN vehicles v ON v.vehicle_id = t.vehicle_id
JOIN route_nodes rp ON rp.route_node_id = rr.pickup_node_id
JOIN route_nodes rd ON rd.route_node_id = rr.drop_node_id
JOIN dispatch_nodes dn ON dn.dispatch_node_id = t.dispatch_node_id;

CREATE VIEW v_driver_review_aggregates AS
SELECT d.driver_id, d.full_name AS driver_name,
       COUNT(rv.review_id) AS review_count,
       ROUND(COALESCE(AVG(rv.rating), 0), 2) AS average_rating
FROM drivers d
LEFT JOIN trips t ON t.driver_id = d.driver_id AND t.trip_status = 'COMPLETED'
LEFT JOIN reviews rv ON rv.trip_id = t.trip_id
GROUP BY d.driver_id, d.full_name;

CREATE VIEW v_vehicle_document_status AS
SELECT v.vehicle_id, v.driver_id, v.vehicle_type, v.registration_no, v.make_model,
       SUM(CASE WHEN vd.document_type = 'REGISTRATION' AND vd.verification_status = 'VERIFIED' AND vd.valid_until >= CURRENT_DATE() THEN 1 ELSE 0 END) AS registration_ok,
       SUM(CASE WHEN vd.document_type = 'INSURANCE' AND vd.verification_status = 'VERIFIED' AND vd.valid_until >= CURRENT_DATE() THEN 1 ELSE 0 END) AS insurance_ok,
       COUNT(vd.document_id) AS document_count
FROM vehicles v LEFT JOIN vehicle_documents vd ON vd.vehicle_id = v.vehicle_id
GROUP BY v.vehicle_id, v.driver_id, v.vehicle_type, v.registration_no, v.make_model;

DELIMITER $$
CREATE TRIGGER trg_review_completed_trip
BEFORE INSERT ON reviews
FOR EACH ROW
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM trips t
        WHERE t.trip_id = NEW.trip_id AND t.trip_status = 'COMPLETED'
    ) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Only completed trips can be reviewed';
    END IF;
END$$

CREATE PROCEDURE sp_match_ride(IN p_request_id BIGINT UNSIGNED)
proc: BEGIN
    DECLARE v_request_status VARCHAR(20);
    DECLARE v_vehicle_type VARCHAR(20);
    DECLARE v_dispatch_node_id BIGINT UNSIGNED;
    DECLARE v_pickup_node_id BIGINT UNSIGNED;
    DECLARE v_drop_node_id BIGINT UNSIGNED;
    DECLARE v_distance DECIMAL(7,2);
    DECLARE v_available_count INT DEFAULT 0;
    DECLARE v_pending_count INT DEFAULT 0;
    DECLARE v_driver_id BIGINT UNSIGNED;
    DECLARE v_vehicle_id BIGINT UNSIGNED;
    DECLARE v_base_fare DECIMAL(8,2);
    DECLARE v_rate DECIMAL(8,2);
    DECLARE v_minimum_fare DECIMAL(8,2);
    DECLARE v_surge DECIMAL(4,2) DEFAULT 1.00;
    DECLARE v_total DECIMAL(10,2);
    DECLARE v_trip_id BIGINT UNSIGNED;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;
    SELECT request_status, vehicle_type, dispatch_node_id, pickup_node_id, drop_node_id, distance_estimate_km
      INTO v_request_status, v_vehicle_type, v_dispatch_node_id, v_pickup_node_id, v_drop_node_id, v_distance
      FROM ride_requests WHERE request_id = p_request_id FOR UPDATE;

    IF v_request_status IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Ride request not found';
    END IF;
    IF v_request_status <> 'PENDING' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Only pending ride requests can be matched';
    END IF;

    SELECT COUNT(*) INTO v_available_count
    FROM v_eligible_driver_vehicles
    WHERE vehicle_type = v_vehicle_type AND dispatch_node_id = v_dispatch_node_id;

    IF v_available_count = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'No eligible driver in this dispatch zone; verify documents or add a driver';
    END IF;

    SELECT COUNT(*) INTO v_pending_count
    FROM ride_requests
    WHERE request_status = 'PENDING'
      AND vehicle_type = v_vehicle_type
      AND dispatch_node_id = v_dispatch_node_id;

    SELECT base_fare, per_km_rate, minimum_fare
      INTO v_base_fare, v_rate, v_minimum_fare
      FROM pricing_rules WHERE vehicle_type = v_vehicle_type;

    SET v_surge = CASE
        WHEN v_pending_count >= (v_available_count * 2) THEN 2.00
        WHEN v_pending_count > v_available_count THEN 1.50
        WHEN v_pending_count * 2 >= v_available_count THEN 1.20
        ELSE 1.00
    END;
    SET v_total = GREATEST(ROUND((v_base_fare + (v_rate * v_distance)) * v_surge, 2), v_minimum_fare);

    SELECT d.driver_id, v.vehicle_id
      INTO v_driver_id, v_vehicle_id
    FROM drivers d
    JOIN vehicles v ON v.driver_id = d.driver_id
    WHERE d.driver_status = 'AVAILABLE'
      AND d.dispatch_node_id = v_dispatch_node_id
      AND v.vehicle_type = v_vehicle_type
      AND v.vehicle_status = 'ACTIVE'
      AND EXISTS (SELECT 1 FROM vehicle_documents vd WHERE vd.vehicle_id = v.vehicle_id AND vd.document_type = 'REGISTRATION' AND vd.verification_status = 'VERIFIED' AND vd.valid_until >= CURRENT_DATE())
      AND EXISTS (SELECT 1 FROM vehicle_documents vd WHERE vd.vehicle_id = v.vehicle_id AND vd.document_type = 'INSURANCE' AND vd.verification_status = 'VERIFIED' AND vd.valid_until >= CURRENT_DATE())
    ORDER BY (d.current_node_id = v_pickup_node_id) DESC, d.driver_id ASC
    LIMIT 1 FOR UPDATE;

    INSERT INTO trips (request_id, driver_id, vehicle_id, dispatch_node_id, trip_status,
                       distance_km, base_fare, per_km_rate, surge_multiplier, total_fare)
    VALUES (p_request_id, v_driver_id, v_vehicle_id, v_dispatch_node_id, 'ASSIGNED',
            v_distance, v_base_fare, v_rate, v_surge, v_total);
    SET v_trip_id = LAST_INSERT_ID();

    INSERT INTO trip_route_nodes (trip_id, sequence_no, route_node_id)
    VALUES (v_trip_id, 1, v_pickup_node_id), (v_trip_id, 2, v_drop_node_id);

    UPDATE ride_requests SET request_status = 'MATCHED' WHERE request_id = p_request_id;
    UPDATE drivers SET driver_status = 'ON_TRIP' WHERE driver_id = v_driver_id;

    COMMIT;
    SELECT v_trip_id AS trip_id, v_driver_id AS driver_id, v_vehicle_id AS vehicle_id,
           v_surge AS surge_multiplier, v_total AS total_fare;
END$$
DELIMITER ;

-- Baseline fare rules (amounts in INR).
INSERT INTO pricing_rules (vehicle_type, base_fare, per_km_rate, minimum_fare) VALUES
('BIKE', 18.00, 7.00, 25.00),
('AUTO', 25.00, 11.00, 35.00),
('CAB', 45.00, 16.00, 60.00);

-- One local dispatch node keeps the demonstration easy to operate; add more zones to show local matching.
INSERT INTO dispatch_nodes (node_name, zone_code, status) VALUES
('Hyderabad Central Dispatch', 'HYD-CENTRAL', 'ACTIVE'),
('Hyderabad West Dispatch', 'HYD-WEST', 'ACTIVE');

INSERT INTO route_nodes (node_name, locality, latitude, longitude, dispatch_node_id) VALUES
('Madhapur Junction', 'Madhapur', 17.448300, 78.391500, 2),
('HITEC City Metro', 'HITEC City', 17.448600, 78.390800, 2),
('Gachibowli Circle', 'Gachibowli', 17.440100, 78.348900, 2),
('Kondapur RTO', 'Kondapur', 17.469800, 78.363900, 2),
('Ameerpet Metro', 'Ameerpet', 17.437500, 78.448300, 1),
('Begumpet Station', 'Begumpet', 17.444800, 78.466200, 1),
('Jubilee Hills Checkpost', 'Jubilee Hills', 17.430000, 78.407000, 1),
('Banjara Hills Road 1', 'Banjara Hills', 17.415600, 78.448000, 1);

INSERT INTO passengers (full_name, phone, email) VALUES
('Aarav Mehta', '9000000101', 'aarav.demo@example.com'),
('Diya Reddy', '9000000102', 'diya.demo@example.com'),
('Kabir Rao', '9000000103', 'kabir.demo@example.com'),
('Anaya Shah', '9000000104', 'anaya.demo@example.com');

-- Demo drivers intentionally cover more than one vehicle category and dispatch zone.
INSERT INTO drivers (full_name, phone, current_node_id, dispatch_node_id, driver_status) VALUES
('Ravi Kumar', '9100000201', 1, 2, 'AVAILABLE'),
('Sana Khan', '9100000202', 3, 2, 'AVAILABLE'),
('Vikram Das', '9100000203', 5, 1, 'AVAILABLE'),
('Meera Joshi', '9100000204', 7, 1, 'OFFLINE');

INSERT INTO vehicles (driver_id, vehicle_type, registration_no, make_model, capacity, vehicle_status) VALUES
(1, 'BIKE', 'TS09-DEMO-101', 'TVS Jupiter', 1, 'ACTIVE'),
(2, 'CAB', 'TS09-DEMO-202', 'Hyundai i20', 4, 'ACTIVE'),
(3, 'AUTO', 'TS09-DEMO-303', 'Bajaj RE', 3, 'ACTIVE'),
(4, 'CAB', 'TS09-DEMO-404', 'Maruti Dzire', 4, 'ACTIVE');

INSERT INTO vehicle_documents (vehicle_id, document_type, document_number, valid_until, verification_status, verified_at) VALUES
(1, 'REGISTRATION', 'REG-DEMO-101', '2028-12-31', 'VERIFIED', NOW()),
(1, 'INSURANCE', 'INS-DEMO-101', '2028-12-31', 'VERIFIED', NOW()),
(2, 'REGISTRATION', 'REG-DEMO-202', '2028-12-31', 'VERIFIED', NOW()),
(2, 'INSURANCE', 'INS-DEMO-202', '2028-12-31', 'VERIFIED', NOW()),
(3, 'REGISTRATION', 'REG-DEMO-303', '2028-12-31', 'VERIFIED', NOW()),
(3, 'INSURANCE', 'INS-DEMO-303', '2028-12-31', 'VERIFIED', NOW()),
(4, 'REGISTRATION', 'REG-DEMO-404', '2028-12-31', 'PENDING', NULL),
(4, 'INSURANCE', 'INS-DEMO-404', '2028-12-31', 'PENDING', NULL);

-- Two requests are provided for immediate matching demonstrations.
INSERT INTO ride_requests (passenger_id, pickup_node_id, drop_node_id, dispatch_node_id, vehicle_type, distance_estimate_km, request_status) VALUES
(1, 1, 3, 2, 'BIKE', 5.80, 'PENDING'),
(2, 5, 8, 1, 'AUTO', 4.20, 'PENDING');
