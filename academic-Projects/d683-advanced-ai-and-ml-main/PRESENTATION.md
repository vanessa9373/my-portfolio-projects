# D683 — Advanced AI and Machine Learning | Project Presentation

**Vanessa Awo | WGU B.S. Computer Science**
**Course:** D683 — Advanced AI and Machine Learning
**Institution:** Western Governors University
**Status:** In Progress

---

## Course Overview

Advanced AI and Machine Learning is the capstone-level AI course in WGU's Computer Science program. It moves beyond supervised learning fundamentals into deep neural networks, natural language processing, computer vision, and model deployment — the skills driving the AI revolution in industry.

This course prepares students to build, train, evaluate, and deploy machine learning models that solve real business problems — not just complete academic exercises.

---

## What This Course Covers

### 1. Deep Learning Architectures
- **Feedforward Neural Networks (FNN)** — architecture design, activation functions (ReLU, sigmoid, tanh, softmax), backpropagation
- **Convolutional Neural Networks (CNNs)** — image classification, feature extraction, pooling layers, transfer learning
- **Recurrent Neural Networks (RNNs)** — sequence modeling, vanishing gradient problem
- **Long Short-Term Memory (LSTM)** — time series prediction, text generation
- **Transformer Architecture** — self-attention mechanism, the foundation of modern LLMs

### 2. Natural Language Processing (NLP)
- Text preprocessing — tokenization, stemming, lemmatization, stop word removal
- Word embeddings — Word2Vec, GloVe, contextual embeddings
- Sentiment analysis and text classification
- Named entity recognition (NER)
- Introduction to large language models (LLMs) and prompt engineering

### 3. Computer Vision
- Image classification with CNNs
- Object detection concepts (YOLO, R-CNN)
- Transfer learning with pre-trained models (ResNet, VGG, MobileNet)
- Data augmentation techniques

### 4. Model Training and Evaluation
- Training pipelines — dataset splitting, batch processing, epoch management
- Regularization — dropout, L1/L2, batch normalization
- Evaluation metrics — accuracy, precision, recall, F1, AUC-ROC, confusion matrix
- Overfitting detection and prevention
- Cross-validation

### 5. Model Deployment
- Exporting and saving trained models (HDF5, ONNX, SavedModel)
- Serving models via REST API (Flask, FastAPI)
- Model versioning and monitoring concepts
- Introduction to MLOps principles

---

## Technologies and Tools

| Tool | Role |
|---|---|
| Python 3 | Core language |
| TensorFlow / Keras | Deep learning framework |
| PyTorch | Alternative deep learning framework |
| Scikit-learn | Classical ML models and evaluation |
| NumPy / Pandas | Data manipulation |
| Matplotlib / Seaborn | Visualization |
| Jupyter Notebook | Experimentation and documentation |
| Hugging Face Transformers | Pre-trained NLP models |
| AWS SageMaker | Cloud-based model training and deployment |

---

## Projects and Experiments

### Image Classification with CNN
Built and trained a Convolutional Neural Network to classify images into categories. Applied transfer learning using a pre-trained ResNet model, fine-tuned on a custom dataset. Achieved significant accuracy improvement over training from scratch with a fraction of the compute cost.

### Sentiment Analysis with NLP
Built a text classification pipeline to analyze customer review sentiment (positive/negative/neutral). Applied tokenization, TF-IDF vectorization, and compared classical ML (Logistic Regression, SVM) against LSTM-based deep learning — documenting the accuracy tradeoff against training complexity.

### Time Series Forecasting with LSTM
Trained an LSTM network to predict future values in a sequential dataset, demonstrating recurrent network architecture, sequence windowing, and the challenge of long-term dependencies.

### Transfer Learning Experiment
Fine-tuned a pre-trained Hugging Face BERT model on a domain-specific text classification task, demonstrating how large pre-trained models can be adapted to new tasks with minimal data — the same technique behind enterprise AI applications.

---

## Connection to AWS AI Services

The concepts learned in this course directly map to AWS AI/ML managed services that I work with as a cloud professional:

| D683 Concept | AWS Service |
|---|---|
| Image classification / Computer Vision | Amazon Rekognition |
| NLP / Text analysis | Amazon Comprehend |
| Custom model training and deployment | Amazon SageMaker |
| Foundation models / LLMs | Amazon Bedrock |
| Real-time inference | SageMaker Endpoints |

Understanding the underlying ML concepts makes me a more effective user of these managed services — I know when to use them, what their limitations are, and how to evaluate their outputs.

---

## Why This Matters to a Hiring Manager

AI and ML are no longer niche specializations — they are core capabilities that every technology company is integrating. This course gives me:

1. **Depth beyond the API call** — I understand how models work, not just how to call them
2. **Practical model-building skills** — CNN, LSTM, NLP pipelines built from scratch
3. **Cloud AI fluency** — direct mapping between theory and AWS AI services
4. **MLOps awareness** — model deployment, versioning, and monitoring concepts
5. **Communication skills** — ability to explain ML decisions to non-technical stakeholders

Whether advising a client on an AI adoption strategy, building a proof-of-concept, or evaluating an AI vendor's claims, this foundation makes me a credible technical voice in AI conversations.

---

## Key Takeaways

> "Advanced AI taught me that machine learning is not magic — it is applied mathematics, statistical inference, and software engineering working together. Understanding the fundamentals gives me the ability to evaluate AI solutions critically, build custom models when needed, and leverage managed services intelligently when they're the right fit."

---

*Vanessa Awo | WGU B.S. Computer Science | github.com/vanessa9373*
