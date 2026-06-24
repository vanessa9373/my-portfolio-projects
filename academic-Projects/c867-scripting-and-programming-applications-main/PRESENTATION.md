# C867 — Scripting and Programming: Applications | Project Presentation

**Vanessa Awo | WGU B.S. Computer Science**
**Course:** C867 — Scripting and Programming: Applications
**Institution:** Western Governors University

---

## Project Overview

This project is a **Student Roster Management System** built in C++ — a console-based application that manages a roster of students, parses raw data, applies object-oriented programming principles, and produces structured output. The project demonstrates core computer science fundamentals: memory management, pointers, OOP design, data structures, and algorithmic thinking — all in a systems-level language where the programmer is responsible for resource management.

C++ is the language of operating systems, game engines, embedded systems, database internals, and high-performance computing. Mastery of C++ fundamentals demonstrates a deep understanding of how software works at the hardware level — knowledge that makes every other language easier to understand and use effectively.

---

## What Was Built

A command-line application that:

### Core Functionality
- **Parses raw student data** from a hardcoded string array — simulating data ingestion from an external source
- **Instantiates Student objects** from parsed data using string manipulation and type conversion
- **Stores students in a dynamic roster array** managed with raw pointers and manual memory allocation
- **Prints all students** in the roster with formatted output
- **Filters students by degree program** — prints only students enrolled in a specific program (e.g., SOFTWARE, SECURITY, NETWORK)
- **Identifies and removes invalid students** — students with negative days-to-complete are flagged and removed
- **Calculates and prints average days to complete** for all students in the roster
- **Releases allocated memory** cleanly using a destructor — preventing memory leaks

### Class Hierarchy

```
Student (Abstract Base Class)
├── Properties: studentID, firstName, lastName, email, age, daysToComplete[3], degreeProgram
├── Methods: print(), getters/setters, constructor/destructor
│
├── NetworkStudent : Student
├── SecurityStudent : Student
└── SoftwareStudent : Student

Roster (Management Class)
├── studentPtrArray[] — array of Student pointers
├── add() — parse and instantiate student from raw data
├── remove() — delete student by ID, release memory
├── printAll() — iterate and print all students
├── printByDegreeProgram() — filter output by enum
├── printDaysInCourse() — calculate averages
├── printInvalidEmails() — validate email format
└── ~Roster() — destructor, frees all heap memory
```

---

## Technologies Used

| Technology | Role |
|---|---|
| C++ (C++14/17) | Core language |
| Object-Oriented Programming | Class design, inheritance, polymorphism |
| Pointers & Dynamic Memory | Heap allocation, `new`, `delete`, pointer arithmetic |
| Enumerations | Degree program type representation |
| String Manipulation | Raw data parsing (substr, find, stoi, stod) |
| Arrays | Roster storage using pointer arrays |
| Destructors | Memory cleanup and resource management |

---

## Key Computer Science Concepts Demonstrated

### Memory Management
Unlike Java or Python, C++ does not have automatic garbage collection. Every `new` allocation must be matched with a `delete`. The `Roster` destructor iterates through the student pointer array and explicitly deletes each object, then sets each pointer to `nullptr`. This demonstrates understanding of the heap, stack, and the cost of memory mismanagement (leaks, dangling pointers, undefined behavior).

### Inheritance and Polymorphism
`Student` is an abstract base class. `NetworkStudent`, `SecurityStudent`, and `SoftwareStudent` each inherit from it, specializing the `print()` method through polymorphism. The roster stores `Student*` pointers, allowing different student types to coexist in a single array — a real-world application of polymorphism.

### Data Parsing
Student data arrives as a raw comma-delimited string. The application manually parses each field using `substr()` and `find()`, converts types with `stoi()` and `stod()`, and instantiates objects — simulating what happens when an application ingests external data with no ORM or framework to help.

### Email Validation
A custom validation method checks each student's email for formatting rules (must contain `@`, must contain `.`, must not contain spaces) — an early example of input validation at the application level.

---

## Why This Matters to a Hiring Manager

C++ skills demonstrate a depth of computer science understanding that few candidates from bootcamps or self-taught backgrounds have. This project shows:

1. **Low-level memory awareness** — I understand what happens when code runs, not just that it runs
2. **OOP from first principles** — inheritance, polymorphism, and encapsulation in a language with no safety net
3. **Data parsing without frameworks** — raw string manipulation, type conversion, error handling
4. **Algorithmic thinking** — filtering, searching, and calculating aggregates over data structures
5. **Resource responsibility** — destructor design, memory ownership, cleanup patterns

These skills directly support roles in systems programming, performance-sensitive back-end work, embedded software, and any environment where understanding the cost of operations matters.

---

## Key Takeaways

> "C++ taught me that programming is ultimately about managing resources — memory, time, and complexity. Understanding these fundamentals at the systems level made me a better programmer in every language I use, because I now understand what the language is doing for me under the hood."

---

*Vanessa Awo | WGU B.S. Computer Science | github.com/vanessa9373*
