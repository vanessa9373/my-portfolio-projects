# D682 — AI Optimization for Computer Scientists | Project Presentation

**Vanessa Awo | WGU B.S. Computer Science**
**Course:** D682 — AI Optimization for Computer Scientists
**Institution:** Western Governors University
**Status:** In Progress

---

## Course Overview

AI Optimization for Computer Scientists focuses on the mathematical and algorithmic foundations that make machine learning systems work efficiently. Where many AI courses focus on applying pre-built models, this course goes deeper — into *why* models learn, *how* they find optimal solutions, and *what* makes one algorithm converge faster or generalize better than another.

This is the course that separates engineers who can use AI tools from engineers who can build and improve them.

---

## What This Course Covers

### 1. Search and Optimization Algorithms
- **Uninformed Search** — Breadth-first search (BFS), Depth-first search (DFS), Uniform cost search
- **Informed Search** — A* search with admissible heuristics, greedy best-first search
- **Local Search** — Hill climbing, simulated annealing, genetic algorithms
- **Constraint Satisfaction Problems (CSPs)** — Backtracking, arc consistency, forward checking

### 2. Gradient-Based Optimization
- Gradient descent (batch, stochastic, mini-batch)
- Learning rate selection and scheduling
- Momentum, RMSProp, and Adam optimizer mechanics
- Convergence analysis and loss landscape visualization

### 3. Probabilistic Models and Inference
- Bayesian networks and conditional probability
- Markov Decision Processes (MDPs)
- Value iteration and policy iteration
- Expectation-Maximization (EM) algorithm

### 4. Hyperparameter Optimization
- Grid search and random search
- Bayesian optimization for hyperparameter tuning
- Cross-validation strategies
- Bias-variance tradeoff and model selection

### 5. Linear and Integer Programming
- Formulating optimization problems as linear programs
- Simplex method concepts
- Constraint modeling for real-world resource allocation problems

---

## Technologies and Tools

| Tool | Application |
|---|---|
| Python 3 | Algorithm implementation |
| NumPy | Numerical computation and matrix operations |
| SciPy | Optimization routines (`scipy.optimize`) |
| Scikit-learn | Model evaluation and cross-validation |
| Matplotlib | Loss curves, convergence visualization |
| Jupyter Notebook | Exploratory analysis and documentation |

---

## Practical Applications Built

### A* Pathfinding Implementation
Implemented A* search from scratch in Python with a custom heuristic function, demonstrating how informed search reduces the search space compared to uninformed BFS. Applied to grid-based navigation problems.

### Gradient Descent from Scratch
Built a gradient descent optimizer in pure NumPy — no ML frameworks — to minimize a cost function for linear regression. Visualized the loss landscape and convergence behavior across different learning rates.

### Genetic Algorithm
Implemented a genetic algorithm with selection, crossover, and mutation operators to solve an optimization problem — demonstrating evolutionary computation as an alternative to gradient-based methods when the loss function is non-differentiable.

### Constraint Satisfaction Solver
Built a backtracking CSP solver with arc consistency (AC-3) to solve scheduling and assignment problems, demonstrating how constraint propagation prunes the search space before backtracking.

---

## Why This Matters to a Hiring Manager

Understanding AI optimization separates practitioners who apply AI from engineers who can improve, debug, and scale it. This course gives me the foundation to:

1. **Debug why a model isn't learning** — understanding gradient flow, vanishing gradients, and learning rate issues
2. **Choose the right optimizer** — knowing when Adam is better than SGD and why
3. **Tune models systematically** — not guessing hyperparameters, but using principled search strategies
4. **Understand AI at scale** — optimization is what makes LLMs, recommendation systems, and autonomous vehicles work
5. **Communicate AI concepts to stakeholders** — I can explain *why* an AI decision was made, not just what it decided

As organizations increasingly integrate AI into their products, engineers who understand the optimization layer are the ones who can solve problems when the model fails in production.

---

## Key Takeaways

> "AI is ultimately an optimization problem. Understanding the math behind how models learn — gradient descent, search, constraint solving — gives me the ability to work with AI systems at a level that goes beyond plugging in pre-built libraries. I understand what's happening inside the black box."

---

*Vanessa Awo | WGU B.S. Computer Science | github.com/vanessa9373*
