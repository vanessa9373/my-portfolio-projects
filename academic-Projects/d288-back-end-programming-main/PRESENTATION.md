# D288 — Back-End Programming | Project Presentation

**Vanessa Awo | WGU B.S. Computer Science**
**Course:** D288 — Back-End Programming
**Institution:** Western Governors University

---

## Project Overview

This project involves building a **back-end REST API** for a travel booking application using Java and Spring Boot. The focus is on designing and implementing server-side business logic, database integration, data validation, and clean API design — foundational skills for any back-end or full-stack engineering role.

This course represents the transition from framework familiarity (D287) to independent back-end system design — building APIs that front-end applications and mobile apps consume in production.

---

## What Was Built

A Spring Boot REST API that serves as the server-side backbone of a travel/vacation booking system, including:

### API Capabilities
- **Excursion management** — Create, read, update, and delete travel excursions
- **Customer management** — Register customers, retrieve profiles, manage bookings
- **Checkout/booking flow** — POST endpoints to confirm reservations tied to customer accounts
- **Data validation** — Input validation at the API boundary to reject malformed or invalid requests before they reach the database
- **Error handling** — Structured error responses with appropriate HTTP status codes

### Application Architecture

```
Client (Angular / Mobile App)
        │
        ▼
  REST Controller Layer     ← @RestController, HTTP verbs, JSON I/O
        │
        ▼
  Service Layer             ← Business logic, validation, orchestration
        │
        ▼
  Repository Layer          ← Spring Data JPA, database queries
        │
        ▼
  H2 / MySQL Database       ← Relational data persistence
```

---

## Technologies Used

| Technology | Role |
|---|---|
| Java 17 | Core language |
| Spring Boot | Application framework |
| Spring Web (REST) | REST API endpoints |
| Spring Data JPA | ORM and database access |
| Hibernate | JPA implementation |
| Bean Validation (JSR-380) | Input validation (`@NotNull`, `@Size`, `@Valid`) |
| H2 / MySQL | Relational database |
| Maven | Build tool |
| Postman | API testing |
| Git / GitLab | Version control |

---

## Key Concepts Applied

### RESTful API Design
All endpoints follow REST principles — correct use of GET, POST, PUT, DELETE HTTP methods, meaningful URL paths, and proper HTTP status codes (200 OK, 201 Created, 400 Bad Request, 404 Not Found, 500 Internal Server Error).

### Bean Validation
Input validation is enforced at the API layer using Java Bean Validation annotations (`@NotNull`, `@NotBlank`, `@Min`, `@Max`, `@Valid`). Invalid requests are rejected with a 400 Bad Request before reaching the database — protecting data integrity and improving API usability.

### Repository Pattern with Spring Data JPA
Repositories extend `JpaRepository` to get CRUD operations, pagination, and sorting for free, with custom query methods defined using Spring Data's method naming convention (e.g., `findByCustomerId`, `findByExcursionName`).

### DTO Pattern
Request and response objects are separate Data Transfer Objects (DTOs), decoupling the API contract from the database entity model. This ensures that internal changes to the database schema don't break external API consumers.

---

## Why This Matters to a Hiring Manager

Back-end programming is the engine of every web and mobile product. This project demonstrates that I can:

- **Design clean REST APIs** that follow HTTP standards and are intuitive for front-end consumers
- **Implement business logic** in a service layer that keeps controllers thin and code testable
- **Validate user input** at the system boundary, protecting against bad data and security risks
- **Work with relational databases** through JPA without writing raw SQL for standard operations
- **Structure a Spring Boot project** following industry conventions that any Java engineer can navigate

These are not academic exercises — they are the exact skills used to build APIs at companies across every industry.

---

## Key Takeaways

> "Back-end programming taught me that great APIs are not just functional — they are predictable, validated, and designed with the consumer in mind. Building this system gave me the discipline to think about API design from the outside in, not just the inside out."

---

*Vanessa Awo | WGU B.S. Computer Science | github.com/vanessa9373*
