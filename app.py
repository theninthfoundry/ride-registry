from __future__ import annotations

import os
from datetime import date
from decimal import Decimal
from typing import Any

import mysql.connector
from dotenv import load_dotenv
from flask import Flask, flash, redirect, render_template, request, url_for
from mysql.connector import Error

load_dotenv()
app = Flask(__name__)
app.secret_key = os.getenv("FLASK_SECRET_KEY", "local-demo-key-change-me")

DB_CONFIG = {
    "host": os.getenv("DB_HOST", "127.0.0.1"),
    "port": int(os.getenv("DB_PORT", "3306")),
    "database": os.getenv("DB_NAME", "ride_registry"),
    "user": os.getenv("DB_USER", "root"),
    "password": os.getenv("DB_PASSWORD", ""),
}


def get_db():
    return mysql.connector.connect(**DB_CONFIG)


def fetch_all(sql: str, params: tuple[Any, ...] = ()) -> list[dict[str, Any]]:
    connection = get_db()
    try:
        cursor = connection.cursor(dictionary=True)
        cursor.execute(sql, params)
        return cursor.fetchall()
    finally:
        cursor.close()
        connection.close()


def fetch_one(sql: str, params: tuple[Any, ...] = ()) -> dict[str, Any] | None:
    rows = fetch_all(sql, params)
    return rows[0] if rows else None


def execute(sql: str, params: tuple[Any, ...] = ()) -> int:
    connection = get_db()
    cursor = connection.cursor()
    try:
        cursor.execute(sql, params)
        connection.commit()
        return int(cursor.lastrowid or 0)
    except Exception:
        connection.rollback()
        raise
    finally:
        cursor.close()
        connection.close()


def execute_procedure(request_id: int) -> dict[str, Any] | None:
    connection = get_db()
    cursor = connection.cursor(dictionary=True)
    try:
        cursor.callproc("sp_match_ride", [request_id])
        result = None
        for result_set in cursor.stored_results():
            result = result_set.fetchone()
        connection.commit()
        return result
    except Exception:
        connection.rollback()
        raise
    finally:
        cursor.close()
        connection.close()


def page_data() -> dict[str, Any]:
    return {"today": date.today().strftime("%d %b %Y")}


@app.context_processor
def inject_globals():
    return {"today_label": date.today().strftime("%d %b %Y")}


@app.route("/")
def dashboard():
    summary = fetch_one("""
        SELECT
          (SELECT COUNT(*) FROM drivers WHERE driver_status = 'AVAILABLE') AS active_drivers,
          (SELECT COUNT(*) FROM ride_requests WHERE request_status = 'PENDING') AS pending_requests,
          (SELECT COUNT(*) FROM trips WHERE trip_status = 'COMPLETED') AS completed_trips,
          (SELECT ROUND(COALESCE(SUM(total_fare), 0), 2) FROM trips WHERE trip_status = 'COMPLETED') AS total_fares,
          (SELECT COUNT(*) FROM v_eligible_driver_vehicles) AS eligible_fleet
    """) or {}
    recent = fetch_all("SELECT * FROM v_trip_registry ORDER BY assigned_at DESC LIMIT 6")
    demand = fetch_all("""
        SELECT dn.node_name AS zone_name, rr.vehicle_type, COUNT(*) AS request_count
        FROM ride_requests rr JOIN dispatch_nodes dn ON dn.dispatch_node_id = rr.dispatch_node_id
        WHERE rr.request_status = 'PENDING'
        GROUP BY dn.node_name, rr.vehicle_type ORDER BY request_count DESC, zone_name LIMIT 5
    """)
    return render_template("dashboard.html", title="Overview", summary=summary, recent=recent, demand=demand)


@app.route("/drivers", methods=["GET", "POST"])
def drivers():
    if request.method == "POST":
        try:
            name = request.form.get("full_name", "").strip()
            phone = request.form.get("phone", "").strip()
            vehicle_type = request.form.get("vehicle_type", "")
            reg_no = request.form.get("registration_no", "").strip().upper()
            make_model = request.form.get("make_model", "").strip()
            node_id = int(request.form.get("current_node_id", "0"))
            reg_doc = request.form.get("registration_doc", "").strip()
            ins_doc = request.form.get("insurance_doc", "").strip()
            if not all([name, phone, vehicle_type, reg_no, make_model, reg_doc, ins_doc]) or node_id <= 0:
                raise ValueError("Complete every driver, vehicle, and document field.")
            route_node = fetch_one("SELECT dispatch_node_id FROM route_nodes WHERE route_node_id=%s", (node_id,))
            if not route_node:
                raise ValueError("Choose a valid current route node.")
            connection = get_db()
            cursor = connection.cursor()
            try:
                cursor.execute("INSERT INTO drivers (full_name, phone, current_node_id, dispatch_node_id, driver_status) VALUES (%s,%s,%s,%s,'AVAILABLE')", (name, phone, node_id, route_node["dispatch_node_id"]))
                driver_id = cursor.lastrowid
                cursor.execute("INSERT INTO vehicles (driver_id, vehicle_type, registration_no, make_model, capacity, vehicle_status) VALUES (%s,%s,%s,%s,%s,'ACTIVE')", (driver_id, vehicle_type, reg_no, make_model, 1 if vehicle_type == "BIKE" else (3 if vehicle_type == "AUTO" else 4)))
                vehicle_id = cursor.lastrowid
                cursor.execute("INSERT INTO vehicle_documents (vehicle_id, document_type, document_number, valid_until, verification_status) VALUES (%s,'REGISTRATION',%s,DATE_ADD(CURRENT_DATE(), INTERVAL 365 DAY),'PENDING'),(%s,'INSURANCE',%s,DATE_ADD(CURRENT_DATE(), INTERVAL 365 DAY),'PENDING')", (vehicle_id, reg_doc, vehicle_id, ins_doc))
                connection.commit()
            except Exception:
                connection.rollback()
                raise
            finally:
                cursor.close()
                connection.close()
            flash("Driver added. Verify both documents before matching rides.", "success")
            return redirect(url_for("drivers"))
        except (ValueError, Error) as exc:
            flash(f"Could not add driver: {exc}", "error")
    fleet = fetch_all("""
        SELECT d.driver_id, d.full_name, d.phone, d.driver_status, rn.node_name AS current_node,
               dn.node_name AS dispatch_name, v.vehicle_type, v.registration_no, v.make_model,
               COALESCE(ds.registration_ok, 0) AS registration_ok, COALESCE(ds.insurance_ok, 0) AS insurance_ok
        FROM drivers d JOIN route_nodes rn ON rn.route_node_id=d.current_node_id
        JOIN dispatch_nodes dn ON dn.dispatch_node_id=d.dispatch_node_id
        JOIN vehicles v ON v.driver_id=d.driver_id
        LEFT JOIN v_vehicle_document_status ds ON ds.vehicle_id=v.vehicle_id
        ORDER BY d.driver_id DESC
    """)
    nodes = fetch_all("SELECT route_node_id, node_name, dispatch_node_id FROM route_nodes ORDER BY node_name")
    return render_template("drivers.html", title="Driver fleet", fleet=fleet, nodes=nodes)


@app.post("/drivers/<int:driver_id>/verify")
def verify_documents(driver_id: int):
    try:
        connection = get_db()
        cursor = connection.cursor()
        try:
            cursor.execute("""
                UPDATE vehicle_documents vd JOIN vehicles v ON v.vehicle_id=vd.vehicle_id
                SET vd.verification_status='VERIFIED', vd.verified_at=NOW()
                WHERE v.driver_id=%s AND vd.document_type IN ('REGISTRATION','INSURANCE')
                  AND vd.valid_until >= CURRENT_DATE()
            """, (driver_id,))
            changed = cursor.rowcount
            if changed < 2:
                connection.rollback()
                flash("Both registration and insurance must be present and unexpired.", "error")
                return redirect(url_for("drivers"))
            connection.commit()
        finally:
            cursor.close()
            connection.close()
        flash("Vehicle documents verified. The driver is eligible when marked available.", "success")
    except Error as exc:
        flash(f"Verification failed: {exc}", "error")
    return redirect(url_for("drivers"))


@app.route("/requests", methods=["GET", "POST"])
def ride_requests():
    if request.method == "POST":
        try:
            passenger_id = int(request.form.get("passenger_id", "0"))
            pickup_id = int(request.form.get("pickup_node_id", "0"))
            drop_id = int(request.form.get("drop_node_id", "0"))
            vehicle_type = request.form.get("vehicle_type", "")
            distance = Decimal(request.form.get("distance_estimate_km", "0"))
            if not passenger_id or not pickup_id or not drop_id or pickup_id == drop_id or distance <= 0 or vehicle_type not in {"BIKE", "AUTO", "CAB"}:
                raise ValueError("Select a passenger, different pickup/drop nodes, vehicle type, and positive distance.")
            pickup = fetch_one("SELECT dispatch_node_id FROM route_nodes WHERE route_node_id=%s", (pickup_id,))
            drop = fetch_one("SELECT dispatch_node_id FROM route_nodes WHERE route_node_id=%s", (drop_id,))
            if not pickup or not drop:
                raise ValueError("Select valid pickup and drop route nodes.")
            if pickup["dispatch_node_id"] != drop["dispatch_node_id"]:
                raise ValueError("For this simple version, pickup and drop must be in the same dispatch zone.")
            execute("INSERT INTO ride_requests (passenger_id, pickup_node_id, drop_node_id, dispatch_node_id, vehicle_type, distance_estimate_km) VALUES (%s,%s,%s,%s,%s,%s)", (passenger_id, pickup_id, drop_id, pickup["dispatch_node_id"], vehicle_type, distance))
            flash("Ride request registered. Match it when a verified driver is available.", "success")
            return redirect(url_for("ride_requests"))
        except (ValueError, Error) as exc:
            flash(f"Could not create request: {exc}", "error")
    passengers = fetch_all("SELECT passenger_id, full_name, phone FROM passengers ORDER BY full_name")
    nodes = fetch_all("SELECT route_node_id, node_name, locality, dispatch_node_id FROM route_nodes ORDER BY locality, node_name")
    requests_list = fetch_all("""
        SELECT rr.*, p.full_name AS passenger_name, rp.node_name AS pickup_name, rd.node_name AS drop_name,
               dn.node_name AS dispatch_name,
               (SELECT COUNT(*) FROM v_eligible_driver_vehicles e WHERE e.vehicle_type=rr.vehicle_type AND e.dispatch_node_id=rr.dispatch_node_id) AS eligible_count
        FROM ride_requests rr JOIN passengers p ON p.passenger_id=rr.passenger_id
        JOIN route_nodes rp ON rp.route_node_id=rr.pickup_node_id
        JOIN route_nodes rd ON rd.route_node_id=rr.drop_node_id
        JOIN dispatch_nodes dn ON dn.dispatch_node_id=rr.dispatch_node_id
        ORDER BY rr.requested_at DESC, rr.request_id DESC
    """)
    return render_template("requests.html", title="Ride requests", passengers=passengers, nodes=nodes, requests_list=requests_list)


@app.post("/requests/<int:request_id>/match")
def match_request(request_id: int):
    try:
        result = execute_procedure(request_id)
        if result:
            flash(f"Ride matched to driver #{result['driver_id']} · surge ×{result['surge_multiplier']} · ₹{result['total_fare']}.", "success")
        else:
            flash("Request matched. Check the trip registry for details.", "success")
    except Error as exc:
        flash(f"Matching failed: {exc}", "error")
    return redirect(url_for("ride_requests"))


@app.route("/trips")
def trips():
    trip_rows = fetch_all("SELECT * FROM v_trip_registry ORDER BY assigned_at DESC, trip_id DESC")
    route_rows = fetch_all("""
        SELECT tr.trip_id, tr.sequence_no, rn.node_name, rn.locality
        FROM trip_route_nodes tr JOIN route_nodes rn ON rn.route_node_id=tr.route_node_id
        ORDER BY tr.trip_id DESC, tr.sequence_no
    """)
    route_by_trip: dict[int, list[dict[str, Any]]] = {}
    for row in route_rows:
        route_by_trip.setdefault(int(row["trip_id"]), []).append(row)
    return render_template("trips.html", title="Trip registry", trip_rows=trip_rows, route_by_trip=route_by_trip)


@app.post("/trips/<int:trip_id>/start")
def start_trip(trip_id: int):
    try:
        connection = get_db()
        cursor = connection.cursor()
        try:
            cursor.execute("UPDATE trips SET trip_status='IN_PROGRESS', started_at=NOW() WHERE trip_id=%s AND trip_status='ASSIGNED'", (trip_id,))
            if cursor.rowcount != 1:
                raise ValueError("Only assigned trips can be started.")
            connection.commit()
        except Exception:
            connection.rollback()
            raise
        finally:
            cursor.close()
            connection.close()
        flash("Trip started.", "success")
    except (ValueError, Error) as exc:
        flash(f"Could not start trip: {exc}", "error")
    return redirect(url_for("trips"))


@app.post("/trips/<int:trip_id>/complete")
def complete_trip(trip_id: int):
    try:
        connection = get_db()
        cursor = connection.cursor()
        try:
            cursor.execute("SELECT t.driver_id, rr.drop_node_id FROM trips t JOIN ride_requests rr ON rr.request_id=t.request_id WHERE t.trip_id=%s AND t.trip_status IN ('ASSIGNED','IN_PROGRESS') FOR UPDATE", (trip_id,))
            row = cursor.fetchone()
            if not row:
                raise ValueError("Trip is not active or does not exist.")
            driver_id, drop_node_id = row
            cursor.execute("UPDATE trips SET trip_status='COMPLETED', completed_at=NOW(), started_at=COALESCE(started_at,NOW()) WHERE trip_id=%s", (trip_id,))
            cursor.execute("UPDATE drivers SET driver_status='AVAILABLE', current_node_id=%s WHERE driver_id=%s", (drop_node_id, driver_id))
            cursor.execute("UPDATE ride_requests t SET request_status='COMPLETED' WHERE request_id=(SELECT request_id FROM trips WHERE trip_id=%s)", (trip_id,))
            connection.commit()
        except Exception:
            connection.rollback()
            raise
        finally:
            cursor.close()
            connection.close()
        flash("Trip completed. Driver is available at the drop node; a review can now be recorded.", "success")
    except (ValueError, Error) as exc:
        flash(f"Could not complete trip: {exc}", "error")
    return redirect(url_for("trips"))


@app.route("/routes", methods=["GET", "POST"])
def routes():
    if request.method == "POST":
        try:
            node_name = request.form.get("node_name", "").strip()
            locality = request.form.get("locality", "").strip()
            dispatch_id = int(request.form.get("dispatch_node_id", "0"))
            lat_text = request.form.get("latitude", "").strip()
            lon_text = request.form.get("longitude", "").strip()
            lat = Decimal(lat_text) if lat_text else None
            lon = Decimal(lon_text) if lon_text else None
            if not node_name or not locality or dispatch_id <= 0:
                raise ValueError("Node name, locality, and dispatch zone are required.")
            execute("INSERT INTO route_nodes (node_name, locality, latitude, longitude, dispatch_node_id) VALUES (%s,%s,%s,%s,%s)", (node_name, locality, lat, lon, dispatch_id))
            flash("Route node added.", "success")
            return redirect(url_for("routes"))
        except (ValueError, Error) as exc:
            flash(f"Could not add route node: {exc}", "error")
    nodes = fetch_all("SELECT rn.*, dn.node_name AS dispatch_name FROM route_nodes rn JOIN dispatch_nodes dn ON dn.dispatch_node_id=rn.dispatch_node_id ORDER BY dn.node_name, rn.locality")
    dispatch_nodes = fetch_all("SELECT dispatch_node_id, node_name, zone_code FROM dispatch_nodes WHERE status='ACTIVE' ORDER BY node_name")
    return render_template("routes.html", title="Route nodes", nodes=nodes, dispatch_nodes=dispatch_nodes)


@app.route("/reviews", methods=["GET", "POST"])
def reviews():
    if request.method == "POST":
        try:
            trip_id = int(request.form.get("trip_id", "0"))
            rating = int(request.form.get("rating", "0"))
            comment = request.form.get("comment", "").strip() or None
            if rating < 1 or rating > 5 or trip_id <= 0:
                raise ValueError("Choose a completed trip and a rating from 1 to 5.")
            execute("INSERT INTO reviews (trip_id, rating, comment) VALUES (%s,%s,%s)", (trip_id, rating, comment))
            flash("Review saved and included in the driver's aggregate rating.", "success")
            return redirect(url_for("reviews"))
        except (ValueError, Error) as exc:
            flash(f"Could not save review: {exc}", "error")
    aggregates = fetch_all("SELECT * FROM v_driver_review_aggregates ORDER BY average_rating DESC, review_count DESC, driver_name")
    eligible_trips = fetch_all("""
        SELECT t.trip_id, p.full_name AS passenger_name, d.full_name AS driver_name,
               rn1.node_name AS pickup_name, rn2.node_name AS drop_name
        FROM trips t JOIN ride_requests rr ON rr.request_id=t.request_id
        JOIN passengers p ON p.passenger_id=rr.passenger_id JOIN drivers d ON d.driver_id=t.driver_id
        JOIN route_nodes rn1 ON rn1.route_node_id=rr.pickup_node_id JOIN route_nodes rn2 ON rn2.route_node_id=rr.drop_node_id
        LEFT JOIN reviews rv ON rv.trip_id=t.trip_id
        WHERE t.trip_status='COMPLETED' AND rv.review_id IS NULL ORDER BY t.completed_at DESC
    """)
    review_rows = fetch_all("""
        SELECT rv.review_id, rv.rating, rv.comment, rv.created_at, t.trip_id,
               p.full_name AS passenger_name, d.full_name AS driver_name
        FROM reviews rv JOIN trips t ON t.trip_id=rv.trip_id JOIN drivers d ON d.driver_id=t.driver_id
        JOIN ride_requests rr ON rr.request_id=t.request_id JOIN passengers p ON p.passenger_id=rr.passenger_id
        ORDER BY rv.created_at DESC
    """)
    return render_template("reviews.html", title="Reviews & ratings", aggregates=aggregates, eligible_trips=eligible_trips, review_rows=review_rows)


@app.errorhandler(Error)
def handle_database_error(error: Error):
    app.logger.exception("Database error", exc_info=error)
    flash("Database connection/query error. Check the .env settings and ensure database/schema.sql was imported.", "error")
    return redirect(url_for("dashboard"))


if __name__ == "__main__":
    app.run(debug=True)
