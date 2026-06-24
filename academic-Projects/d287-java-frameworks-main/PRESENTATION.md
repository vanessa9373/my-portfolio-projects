# D287 — Java Frameworks | Project Presentation

**Vanessa Awo | WGU B.S. Computer Science**
**Course:** D287 — Java Frameworks
**Institution:** Western Governors University

---

## Project Overview

This project is a fully functional **Inventory Management Web Application** built using the Spring Boot framework, Spring Data JPA, and the Thymeleaf templating engine. The application allows users to manage a catalog of parts and assembled products — tracking inventory levels, pricing, and supplier relationships — through a browser-based interface backed by a persistent database.

This project demonstrates the ability to build production-grade, enterprise Java web applications using the same frameworks and architecture patterns used by companies like Amazon, Netflix, and Spotify in their microservices and back-end systems.

---

## What Was Built

A complete CRUD (Create, Read, Update, Delete) inventory management system with:

### Core Domain Model
- **Parts** — Components used to build products, modeled as an abstract class with two concrete types:
  - `InhousePart` — manufactured in-house with a machine ID
  - `OutsourcedPart` — sourced from an external company, with company name tracking
- **Products** — Assembled goods made from one or more parts, with inventory tracking and pricing

### Application Layers (MVC Architecture)

| Layer | Technology | Responsibility |
|---|---|---|
| Presentation | Thymeleaf + HTML | User interface — forms, tables, confirmations |
| Controller | Spring MVC | Handle HTTP requests, routing, form submission |
| Service | Spring Service beans | Business logic and validation rules |
| Repository | Spring Data JPA | Database queries and persistence |
| Database | H2 (in-memory) | Data storage |

### Features Implemented
- Add, update, and delete **inhouse parts** and **outsourced parts**
- Add, update, and delete **products** with associated parts
- Enforce **inventory validation** — minimum and maximum stock levels
- Enforce **price validation** — product price cannot be less than the sum of its parts
- **Delete protection** — prevent deletion of a part that is still associated with a product
- Confirmation pages for all destructive actions
- Error messaging for validation failures
- Bootstrap data loader to pre-populate the application on startup

---

## Technologies Used

| Technology | Version | Role |
|---|---|---|
| Java | 17 | Core programming language |
| Spring Boot | 2.x | Application framework and auto-configuration |
| Spring MVC | — | Model-View-Controller web layer |
| Spring Data JPA | — | Repository abstraction and ORM |
| Hibernate | — | JPA implementation / database mapping |
| Thymeleaf | — | Server-side HTML templating |
| H2 Database | — | In-memory relational database |
| Maven | — | Dependency management and build tool |
| IntelliJ IDEA | Ultimate | IDE |
| JUnit 5 | — | Unit and integration testing |
| Git / GitLab | — | Version control |

---

## Architecture Deep Dive

### Inheritance and Polymorphism
The `Part` class is abstract with `InhousePart` and `OutsourcedPart` as concrete subclasses, mapped to a single database table using JPA's `@Inheritance` strategy. This demonstrates proper OOP design — shared behavior lives in the parent, specialized behavior in the subclasses.

### Custom Validators
Three custom Spring validators were built from scratch:
- `EnufPartsValidator` — ensures sufficient part inventory exists before associating with a product
- `PriceProductValidator` — ensures product price ≥ sum of associated part prices
- `DeletePartValidator` — blocks deletion if the part is still used in a product

Each validator implements Spring's `Validator` interface, demonstrating knowledge of the Spring validation lifecycle and how to integrate business rules at the framework level.

### Service Layer
The service layer decouples business logic from the controller and repository. Each entity (Part, Product, InhousePart, OutsourcedPart) has an interface and implementation — a pattern that enables dependency injection, testability, and future swappability of implementations.

### Testing
JUnit 5 tests cover:
- Domain model behavior (`InhousePartTest`, `OutsourcedPartTest`, `PartTest`, `ProductTest`)
- Repository queries (`InhousePartRepositoryTest`)
- Service layer logic (`InhousePartServiceTest`)

---

## Why This Matters to a Hiring Manager

Spring Boot is the dominant Java web framework in enterprise software. This project demonstrates that I can:

1. **Design a multi-layer enterprise application** — not just write code, but structure it into controllers, services, repositories, and domain models following separation of concerns
2. **Build and enforce business rules** — custom validators, inventory constraints, price logic
3. **Work with ORM and relational databases** — JPA entity mapping, relationships, queries
4. **Write tests** — unit tests for domain objects, repository tests, service tests
5. **Deliver a working, usable application** — not just a skeleton, but a functioning product with real UI, real data, real validation

These skills apply directly to any back-end Java engineering role, and the architectural patterns (MVC, service layer, repository pattern, dependency injection) are language-agnostic concepts that transfer to Python, Go, and Node.js environments as well.

---

## Key Takeaways

> "Building this inventory system taught me how enterprise Java applications are structured at scale — not just how to write Java, but how to organize a Spring application so it remains maintainable, testable, and extensible as requirements grow."

---

*Vanessa Awo | WGU B.S. Computer Science | github.com/vanessa9373*
