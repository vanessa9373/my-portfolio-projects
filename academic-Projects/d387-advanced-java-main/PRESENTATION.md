# D387 — Advanced Java | Project Presentation

**Vanessa Awo | WGU B.S. Computer Science**
**Course:** D387 — Advanced Java
**Institution:** Western Governors University

---

## Project Overview

This project is a **Hotel Reservation System** — a full-stack web application with a Java/Spring Boot REST API back-end and an Angular front-end — enhanced with multithreading, internationalization (i18n), multi-timezone support, currency exchange, and Docker containerization.

This project represents the highest level of complexity in the WGU Java curriculum. It bridges back-end API design, concurrent programming, front-end integration, and cloud-ready deployment — skills that map directly to real-world software engineering roles.

---

## What Was Built

### Full-Stack Architecture

```
┌─────────────────────────────────┐
│      Angular Front-End (UI)     │  ← Served as static assets by Spring Boot
│  Room search · Date picker      │
│  Reservation form · Booking UI  │
└────────────────┬────────────────┘
                 │ HTTP / REST (JSON)
┌────────────────▼────────────────┐
│   Spring Boot REST API (Java)   │  ← Core back-end
│  /api/v1/room-reservations      │
│  GET · POST · PUT · DELETE      │
└────────────────┬────────────────┘
                 │ JPA / Hibernate
┌────────────────▼────────────────┐
│         H2 In-Memory DB         │  ← Relational data store
│  Rooms table · Reservations     │
└─────────────────────────────────┘
```

### REST API Endpoints

| Method | Endpoint | Description |
|---|---|---|
| `GET` | `/api/v1/room-reservations` | Get available rooms by check-in/check-out date |
| `GET` | `/api/v1/room-reservations/{roomId}` | Get a specific room by ID |
| `POST` | `/api/v1/room-reservations` | Create a new reservation |
| `PUT` | `/api/v1/room-reservations` | Update an existing reservation |
| `DELETE` | `/api/v1/room-reservations/{id}` | Cancel a reservation |

### Room Availability Algorithm
The GET endpoint implements a real availability check: given a check-in and check-out date, it queries all rooms and all reservations, then filters out any room where the requested dates overlap with an existing booking. This involves date range intersection logic handling three overlap scenarios: checkin before existing checkin, checkin during existing stay, and exact checkin match.

---

## Advanced Features Implemented

### 1. Multithreading — Concurrent Language Translation
Implemented Java multithreading to display welcome messages in **multiple languages simultaneously** using `Thread`, `Runnable`, and `ExecutorService`. Each translation runs in its own thread, demonstrating concurrent execution, thread lifecycle management, and thread-safe output handling.

### 2. Internationalization (i18n) & Localization
Configured Spring's `LocaleResolver` and `MessageSource` to support multiple locales. Resource bundles externalize user-facing strings, allowing the application to display content in different languages without changing the core code — a critical requirement for any global-facing application.

### 3. Multi-Timezone Support
Added a feature that displays the current time across multiple time zones simultaneously (ET, MT, UTC). Used Java's `ZonedDateTime` and `ZoneId` APIs, again executed concurrently via multithreading to show multiple timezone outputs at the same time.

### 4. Currency Exchange Display
Integrated currency conversion to display room prices in multiple currencies, demonstrating data transformation and formatting for an international user base.

### 5. Docker Containerization
Built a `Dockerfile` and containerized the complete Spring Boot application (back-end + Angular front-end bundled together) into a single Docker image. This makes the application:
- **Environment-independent** — runs identically on any machine with Docker
- **Cloud-ready** — deployable to AWS ECS, EKS, GCP Cloud Run, or Azure Container Apps
- **Reproducible** — eliminates "works on my machine" issues

---

## Technologies Used

| Technology | Role |
|---|---|
| Java 17 | Core back-end language |
| Spring Boot | Application framework |
| Spring Data JPA / Hibernate | ORM and database persistence |
| Spring REST (RestController) | REST API layer |
| Angular | Front-end SPA framework |
| TypeScript | Angular component language |
| H2 Database | In-memory relational database |
| Java Multithreading | Concurrent language translation and timezone display |
| Docker | Application containerization |
| Maven | Build and dependency management |
| IntelliJ IDEA | IDE |
| Git / GitLab | Version control |

---

## Architecture Highlights

### Converter Pattern
The application uses Spring's `ConversionService` with custom converters:
- `ReservationEntityToReservationResponseConverter` — transforms DB entities into API response DTOs
- `ReservationRequestToReservationEntityConverter` — transforms API requests into DB entities
- `RoomEntityToReservableRoomResponseConverter` — transforms room entities for the availability API

This separates the database model from the API contract — a critical architectural pattern that prevents tight coupling between layers and makes the API safe to evolve without breaking the database schema.

### Pagination
Room availability results are returned as a `Page<ReservableRoomResponse>` using Spring Data's `Pageable`, enabling efficient large dataset handling and front-end pagination support.

### Cross-Origin Resource Sharing (CORS)
Configured `@CrossOrigin` on the REST controller to allow the Angular front-end (running on a different port during development) to communicate with the Spring Boot API — real-world web security configuration.

---

## Why This Matters to a Hiring Manager

This project touches almost every layer of a production back-end system:

| Skill | Evidence in This Project |
|---|---|
| REST API design | CRUD endpoints with proper HTTP methods and status codes |
| Concurrent programming | Multithreaded translation and timezone display |
| Full-stack integration | Spring Boot + Angular communicating via REST |
| Database ORM | JPA entities, repositories, relationships |
| Containerization | Docker image build and deployment |
| Software architecture | Converter pattern, DTO separation, layered design |
| Internationalization | Multi-locale, multi-timezone, multi-currency support |

The combination of concurrency, full-stack, and containerization in one project reflects the breadth expected of a mid-level software engineer — and demonstrates that I can navigate a complex, multi-technology codebase confidently.

---

## Key Takeaways

> "This project taught me how to think beyond writing code — how to architect a system that is concurrent, internationally accessible, and deployable to any cloud environment. These are the skills that separate a software developer from a software engineer."

---

*Vanessa Awo | WGU B.S. Computer Science | github.com/vanessa9373*
