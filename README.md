# Ride Registry — DBMS PBL

A small, demonstrable ride-hailing registry built with **MySQL 8 + Python Flask**. It manages passengers, local dispatch zones, drivers, vehicle documents, ride requests, surge-aware matching, trip routes, and driver review aggregates.

> **Scope note:** “Decentralized” is represented as independent local dispatch nodes/zones that match rides locally. This classroom prototype uses one MySQL database; it does not claim to implement blockchain or distributed consensus.

## Features

- Dashboard with live counts and fare totals.
- Driver and vehicle registry with registration/insurance document verification.
- Ride request creation and driver matching.
- Dynamic pricing based on vehicle category and the ratio of pending demand to eligible drivers.
- Trip lifecycle: assigned → in progress → completed.
- Ordered pickup/drop route nodes stored per trip.
- Customer reviews and SQL view-based driver rating aggregates.
- MySQL foreign keys, checks, indexes, a stored procedure, views, and a trigger for DBMS demonstration.

## Requirements

- Python 3.10+
- MySQL 8.0+

## Run locally

1. Create and activate a virtual environment (recommended).
2. Install dependencies:

   ```bash
   pip install -r requirements.txt
   ```

3. Create the database, tables, views, procedure, trigger, and sample records:

   ```bash
   mysql -u root -p < database/schema.sql
   ```

4. Copy `.env.example` to `.env` and set your MySQL username/password.
5. Start the app:

   ```bash
   python app.py
   ```

6. Open `http://127.0.0.1:5000`.

The SQL file creates demo data for Hyderabad localities. To reset the demo database, rerun `database/schema.sql`; it drops and recreates `ride_registry`.

## Suggested viva explanation

- **Primary/foreign keys** preserve entity identity and referential integrity.
- **Normalization** separates passengers, drivers, vehicles, documents, requests, trips, route nodes, reviews, and pricing rules instead of duplicating data.
- **Stored procedure `sp_match_ride`** performs transactional matching and stores the computed fare/surge multiplier.
- **Views** provide an active eligible fleet, trip registry, and review aggregates.
- **Trigger `trg_review_completed_trip`** prevents reviews for trips that have not completed.
- **Indexes** support dispatch lookups by status, vehicle type, and local node.

## Deliberate simplifications

This is a local academic/admin demo, not a public ride-hailing product. It has no payment gateway, maps API, real GPS, public signup, or authentication. Distances are entered for the demo, and matching is zone-local with nearest-node preference (same pickup node first), then stable driver-ID ordering.
