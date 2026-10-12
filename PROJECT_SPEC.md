# Project spec: Ride Registry

## One-line purpose
A small dispatch registry that validates a vehicle, matches a pending ride to an eligible local driver, calculates a demand-aware fare, records the route and trip lifecycle, and aggregates customer reviews.

## Required scope → implementation

| Requirement from the brief | Implementation |
|---|---|
| Active drivers | `drivers.driver_status`; dashboard and Driver Fleet screen |
| Vehicle documents | `vehicles`, `vehicle_documents`; only valid, verified registration + insurance are match-eligible |
| Passenger ride requests | `passengers`, `ride_requests`; create and list requests |
| Dynamic trip pricing | `pricing_rules` + `sp_match_ride`; final fare and surge are saved to `trips` |
| Route nodes | `dispatch_nodes`, `route_nodes`, `trip_route_nodes`; ordered pickup/drop references per trip |
| Customer review aggregates | `reviews`, `v_driver_review_aggregates`; average rating and count per driver |
| Decentralized/local matching idea | Dispatch zones maintain their own local pool. The classroom build simulates this concept in one MySQL database. |

## Pricing rule

`fare = max(minimum_fare, (base_fare + distance_km × per_km_rate) × surge_multiplier)`

The current procedure uses the count of pending requests versus currently eligible drivers in the same dispatch zone and vehicle class. It uses four simple bands: baseline (×1.00), elevated demand (×1.20), demand above supply (×1.50), and very high demand (×2.00). The multiplier and rule inputs are stored on each trip for auditability.

## Matching rule

1. Request must be `PENDING`.
2. Candidate driver must be `AVAILABLE` and belong to an `ACTIVE` dispatch zone.
3. Candidate must operate an active vehicle of the requested class.
4. Registration and insurance must both be verified and unexpired.
5. Prefer a driver whose current route node is the pickup node; otherwise use stable driver ID order.
6. Create the trip and ordered route nodes; mark the request `MATCHED` and driver `ON_TRIP` in one transaction.

## Screens

1. **Overview:** four useful metrics, recent trip registry, pending demand by local zone.
2. **Ride Requests:** request intake, eligible supply count, one-click match.
3. **Driver Fleet:** vehicle details, location, document status, document verification.
4. **Trip Registry:** route stops, fare breakdown, start/complete actions.
5. **Route Nodes:** create and view locations by dispatch zone.
6. **Reviews:** leave one review per completed trip and inspect rating aggregates.

## Non-goals (kept out to protect project simplicity)

No blockchain, cryptocurrency, payment gateway, map API, live GPS tracking, public customer login, or production authentication. Those features are not needed to demonstrate the specified database relationships and queries.
