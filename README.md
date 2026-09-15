# 🚸 School/College Pick-and-Drop Management System

> A digital school and college transportation management system designed to provide safe, organized, and transparent communication between parents, verified drivers, and administrators.

**Final Year Project (FYP) — Bachelor of Science in Software Engineering**

---

## 📑 Table of Contents

1. [Project Overview](#-project-overview)
2. [Problem Statement](#-problem-statement)
3. [Project Objectives](#-project-objectives)
4. [Key Features](#-key-features)

   * [Parent Mobile App](#-parent-mobile-app)
   * [Driver Mobile App](#-driver-mobile-app)
   * [Admin Web Panel](#-admin-web-panel)
   * [Super Admin Web Panel](#-super-admin-web-panel)
5. [Technology Stack](#-technology-stack)
6. [System Architecture](#-system-architecture)
7. [Project Structure](#-project-structure)
8. [Main Modules](#-main-modules)
9. [Firebase Integration](#-firebase-integration)
10. [Google Maps Integration](#-google-maps-integration)
11. [AI-Based Review Sentiment Analysis](#-ai-based-review-sentiment-analysis)
12. [User Workflow](#-user-workflow)
13. [Installation & Setup](#-installation--setup)
14. [System Requirements](#-system-requirements)
15. [Future Enhancements](#-future-enhancements)
16. [Project Team](#-project-team)
17. [Academic Information](#-academic-information)

---

## 📌 Project Overview

The **School/College Pick-and-Drop Management System** is a multi-platform transportation management solution developed to improve the safety, reliability, and organization of student transportation.

The system connects four main stakeholders:

* 👨‍👩‍👧 **Parents**
* 🚍 **Drivers**
* 🏢 **Administrators**
* 👑 **Super Administrators**

Parents can register their children, request transportation services, view assigned drivers, track vehicles, receive pickup/drop-off notifications, make payments, and provide driver reviews.

Drivers can register, submit their vehicle and identification information for verification, manage routes and students, start and complete rides, and provide real-time location updates.

Administrators manage drivers, parents, students, schools, routes, requests, complaints, reviews, and transportation operations.

Super Administrators manage administrators, financial records, payments, reports, and system activity logs.

---

## ❗ Problem Statement

Traditional school and college pick-and-drop services often depend on informal transportation arrangements and manual communication.

These approaches can create problems such as:

* Lack of verified drivers
* Limited visibility of vehicle location
* Difficulty tracking children during transportation
* Manual pickup and drop-off coordination
* Lack of proper route management
* Difficulty handling transportation requests
* Unorganized fee and payment records
* No centralized complaint and review system
* Limited administrative monitoring

The proposed system addresses these problems by providing a centralized digital platform for managing student transportation.

---

## 🎯 Project Objectives

The main objectives of the system are:

* Provide a centralized student transportation platform.
* Allow administrators to verify and manage drivers.
* Provide parents with real-time vehicle tracking.
* Manage student pickup and drop-off activities digitally.
* Provide route and school management.
* Improve communication between parents and drivers.
* Provide notifications for important ride events.
* Enable digital transportation payments.
* Collect and analyze parent feedback.
* Provide administrators with reports and monitoring tools.
* Improve overall safety, transparency, and efficiency.

---

# 🚀 Key Features

## 👨‍👩‍👧 Parent Mobile App

The Parent application allows parents to manage their children's transportation.

### Features

* Parent registration and login
* Profile management
* Add child information
* Select school/college
* Add pickup and drop-off location
* Submit transportation requests
* View assigned driver information
* View route and transportation details
* View available seats and pricing
* Real-time child/vehicle GPS tracking
* Pickup notifications
* Drop-off notifications
* Route deviation notifications
* Driver unavailable notifications
* Driver reviews and ratings
* AI-based review sentiment analysis
* In-app communication with driver
* Transportation payment
* View transportation information
* Logout

---

## 🚍 Driver Mobile App

The Driver application provides drivers with tools to manage their transportation duties.

### Features

* Driver registration and login
* Driver profile management
* Upload identification and vehicle documents
* Vehicle information management
* Administrator verification
* Pending approval status
* Route management
* Schedule management
* Seat/capacity management
* View assigned students
* View parent information
* Start ride
* Pickup student
* Drop off student
* Complete ride
* Real-time GPS location sharing
* Route monitoring
* Ride status management
* Earnings information
* Trip history
* Parent communication
* Driver feedback and reviews

### Driver Verification

New drivers are not immediately allowed to operate.

The workflow is:

```text
Driver Registration
        ↓
Profile & Document Submission
        ↓
Administrator Review
        ↓
Approval / Rejection
        ↓
Approved Driver
        ↓
Driver Dashboard
```

This helps ensure that only verified drivers can provide transportation services.

---

# 🏢 Admin Web Panel

The Admin web panel is designed for school/branch transportation management.

### Features

* Admin login
* Dashboard
* Parent management
* Driver management
* Driver verification
* Driver approval/rejection
* School management
* Route management
* Transportation request management
* Student assignment
* Driver assignment
* Live vehicle monitoring
* Review management
* Complaint management
* Reports
* Activity monitoring
* Deleted record recovery

The Admin manages the day-to-day transportation operations of the system.

---

# 👑 Super Admin Web Panel

The Super Admin has higher-level control over the entire system.

### Features

* Super Admin login
* Dashboard
* Admin management
* Add administrators
* Manage administrators
* Restore deleted administrators
* Payment management
* Revenue and commission tracking
* Financial ledger
* Admin salary management
* Activity logs
* Deleted records
* Record recovery
* Reports and system monitoring

The Super Admin provides centralized management and oversight of the platform.

---

# 🛠️ Technology Stack

| Category             | Technology              | Purpose                               |
| -------------------- | ----------------------- | ------------------------------------- |
| Mobile Application   | Flutter                 | Parent and Driver mobile applications |
| Programming Language | Dart                    | Flutter application development       |
| Admin Web Panel      | React.js                | Admin and Super Admin dashboards      |
| Web Language         | JavaScript              | Frontend functionality                |
| Backend / Database   | Firebase                | Cloud-based application services      |
| Authentication       | Firebase Authentication | User authentication                   |
| Database             | Cloud Firestore         | Real-time data storage                |
| File Storage         | Firebase Storage        | Driver documents and images           |
| Maps                 | Google Maps API         | Maps, routes and location tracking    |
| Routing              | Google Directions API   | Road route and path generation        |
| Sentiment Analysis   | VADER / TextBlob        | Review sentiment classification       |
| Design               | Figma                   | UI/UX design and prototyping          |
| Local Storage        | LocalStorage            | Storing user favorites and local data |

---

# 🏗️ System Architecture

The system follows a layered application architecture:

```text
┌─────────────────────────────────────────────┐
│              Presentation Layer             │
│                                             │
│   Flutter Mobile Apps     React Web Panels  │
│   Parent + Driver         Admin + SuperAdmin│
└──────────────────────┬──────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────┐
│             Business Logic Layer            │
│                                             │
│ Authentication • Ride Management            │
│ Route Management • Payments • Reviews       │
│ Notifications • GPS Tracking                │
└──────────────────────┬──────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────┐
│               Data Access Layer             │
│                                             │
│ Repository / CRUD Operations                 │
│ Firebase Data Operations                    │
└──────────────────────┬──────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────┐
│                 Firebase                    │
│                                             │
│ Authentication • Firestore • Storage       │
└─────────────────────────────────────────────┘
```

---

# 📂 Project Structure

The project is organized into separate applications for mobile and web platforms.

```text
Pick-and-Drop-Management-System/
│
├── app/
│   └── transport_app/
│       ├── android/
│       ├── ios/
│       ├── web/
│       ├── lib/
│       │   ├── config/
│       │   ├── screens/
│       │   ├── services/
│       │   ├── theme/
│       │   ├── utils/
│       │   ├── firebase_options.dart
│       │   └── main.dart
│       ├── pubspec.yaml
│       └── README.md
│
├── admin/
│   └── admin-web/
│       ├── public/
│       ├── src/
│       │   ├── components/
│       │   ├── contexts/
│       │   ├── lib/
│       │   ├── pages/
│       │   ├── firebase.js
│       │   ├── App.js
│       │   └── index.js
│       ├── package.json
│       └── README.md
│
├── .gitignore
└── README.md
```

---

# 📱 Main Mobile Screens

### Parent

```text
Login
Signup
        ↓
Parent Dashboard
        ↓
Profile
Add Child
View Routes
View Driver
Live Tracking
Payments
Reviews
Chat
```

### Driver

```text
Login
Signup
        ↓
Profile Completion
        ↓
Pending Approval
        ↓
Driver Dashboard
        ↓
Route
Students
Start Ride
Pickup
Drop-off
Complete Ride
Earnings
```

---

# 🔥 Firebase Integration

Firebase is used as the main cloud platform for the system.

## Firebase Authentication

Used for:

* Parent registration/login
* Driver registration/login
* Admin authentication
* Super Admin authentication
* Authentication state management
* Role-based access

## Cloud Firestore

Firestore stores application data such as:

* Users
* Parents
* Drivers
* Children
* Schools
* Routes
* Transportation requests
* Rides
* Payments
* Reviews
* Complaints
* Reports
* Activity logs

## Firebase Storage

Used for storing files and images such as:

* Driver profile images
* Driver license documents
* Vehicle documents
* Other uploaded verification documents

---

# 🗺️ Google Maps Integration

Google Maps is integrated into the system to support transportation and location-based functionality.

### Main Features

* Display maps
* Pickup location
* Drop-off location
* Driver location
* Parent location
* Route visualization
* Real-time vehicle tracking
* Route deviation detection
* Road-following route paths
* School location
* Driver route monitoring

Google Directions API is used for generating road-based routes and polylines.

---

# 🤖 AI-Based Review Sentiment Analysis

The system includes an AI-assisted review evaluation feature.

Parents can submit reviews about drivers after transportation services.

The review system classifies feedback into:

```text
Positive
   ↓
Neutral
   ↓
Negative
```

### Example

```text
"Driver was polite and always arrived on time."
                    ↓
               Positive
```

```text
"Driver was frequently late."
                    ↓
               Negative
```

The sentiment results can be used by administrators to monitor driver performance and identify repeated negative feedback.

### Purpose

* Analyze parent feedback
* Identify positive experiences
* Detect negative reviews
* Monitor driver performance
* Generate useful reports
* Support administrative decision-making

---

# 💳 Payment Management

The system provides digital transportation payment functionality.

Parents can manage transportation payments through the application.

The financial management module also allows higher-level administrators to monitor:

* Parent payments
* Driver earnings
* Platform commission
* Financial records
* Transaction history
* Administrator salaries

---

# 🔔 Notifications

The system provides notifications for important transportation events.

Examples include:

* Ride started
* Child picked up
* Child dropped off
* Driver unavailable
* Route deviation
* Transportation status updates

This helps parents stay informed about their child's transportation status.

---

# 🔄 User Workflow

The complete system workflow can be summarized as:

```text
                 ┌───────────────┐
                 │     Parent    │
                 └───────┬───────┘
                         │
                    Register
                         │
                         ▼
                 Add Child / Request
                         │
                         ▼
                 ┌───────────────┐
                 │     Admin     │
                 └───────┬───────┘
                         │
                  Assign Driver
                         │
                         ▼
                 ┌───────────────┐
                 │     Driver    │
                 └───────┬───────┘
                         │
                    Start Ride
                         │
                         ▼
                  Pickup Student
                         │
                         ▼
                  Live GPS Tracking
                         │
                         ▼
                  Drop-off Student
                         │
                         ▼
                 Parent Review
                         │
                         ▼
                 Sentiment Analysis
                         │
                         ▼
                 Admin Monitoring
```

---

# 🔐 Role-Based Access Control

The system provides different permissions according to user roles.

| Role        | Main Responsibilities                                     |
| ----------- | --------------------------------------------------------- |
| Parent      | Manage children, requests, tracking, payments and reviews |
| Driver      | Manage rides, routes, students and GPS location           |
| Admin       | Manage drivers, parents, schools, routes and requests     |
| Super Admin | Manage admins, payments, salaries, reports and logs       |

This ensures that users can only access functionality relevant to their role.

---

# 📥 Installation & Setup

## Prerequisites

Before running the project, install:

* Flutter SDK
* Dart SDK
* Android Studio
* Android SDK
* JDK 17
* Node.js
* npm
* Firebase account
* Google Cloud account
* Google Maps API access

---

## 📱 Flutter Mobile Application

Navigate to the mobile application:

```bash
cd app/transport_app
```

Install Flutter dependencies:

```bash
flutter pub get
```

Check connected devices:

```bash
flutter devices
```

Run the application:

```bash
flutter run
```

---

## 💻 React Admin Panel

Navigate to:

```bash
cd admin/admin-web
```

Install dependencies:

```bash
npm install
```

Start the development server:

```bash
npm start
```

The React application will normally run on:

```text
http://localhost:3000
```

---

# ⚙️ Firebase Setup

1. Create a Firebase project.
2. Enable Firebase Authentication.
3. Enable Email/Password authentication.
4. Create a Cloud Firestore database.
5. Enable Firebase Storage.
6. Register the required Android and Web applications.
7. Configure Firebase credentials.
8. Add the required Firebase configuration files.

For Flutter, Firebase configuration can be generated using FlutterFire CLI:

```bash
flutterfire configure
```

---

# 🗺️ Google Maps Setup

Create a Google Cloud project and enable the required APIs.

Required services may include:

* Maps SDK for Android
* Maps SDK for iOS
* Maps JavaScript API
* Places API
* Directions API

Configure the Google Maps API key according to the mobile and web application requirements.

---

# 🧪 Testing

The system includes functional testing for important application workflows.

Examples of tested Parent functionalities include:

| Test Case | Functionality                   |
| --------- | ------------------------------- |
| TC_P_001  | Registration                    |
| TC_P_002  | Login                           |
| TC_P_003  | Update Profile                  |
| TC_P_004  | Add Child                       |
| TC_P_005  | Edit Child                      |
| TC_P_006  | Delete Child                    |
| TC_P_007  | View Driver Profile             |
| TC_P_009  | Live GPS Tracking               |
| TC_P_010  | Pickup Notification             |
| TC_P_011  | Drop Notification               |
| TC_P_012  | Route Deviation Notification    |
| TC_P_013  | Driver Unavailable Notification |
| TC_P_016  | Submit Review                   |
| TC_P_017  | Logout                          |

Automation testing was also performed for web-based administrative functionality using:

* Java
* Selenium
* TestNG
* Maven

---

# 💻 System Requirements

### Software

* Android 8.0 or higher
* Flutter SDK
* Dart
* Node.js and npm
* JDK 17
* Android Studio
* Modern web browser
* Firebase account
* Google Cloud account

### Network

An active internet connection is required for:

* Firebase services
* Authentication
* Firestore
* GPS synchronization
* Google Maps
* Route services
* Online payments

### Performance

The system is designed to provide responses within approximately **3–5 seconds** under normal network conditions.

---

# 🔮 Future Enhancements

Future versions of the system can include:

* AI-based route optimization
* Automatic route assignment
* Advanced driver performance prediction
* AI-based demand forecasting
* Emergency SOS functionality
* Advanced parent-child safety monitoring
* Automated attendance
* More advanced analytics dashboards
* Multi-school and multi-city expansion
* Additional payment methods
* Advanced notification services

---

## 👥 Project Team

### Aiman Shabbir — Lead Mobile Application & Frontend Developer

* Developed the Flutter-based Parent and Driver mobile applications
* Designed and implemented mobile application screens and workflows
* Developed React-based Admin and Super Admin frontend panels
* Integrated Firebase Authentication and Firestore
* Implemented GPS tracking and Google Maps functionality
* Worked on UI/UX, integration, testing, and project documentation

### Areeba Khan — Backend Developer & Database Architect

* Designed and managed the Firebase backend infrastructure
* Designed and structured the Firestore database and collections
* Implemented backend data operations and database integration
* Managed user, driver, parent, child, route, payment, and review data
* Worked on Firebase Authentication, Firestore, and Firebase Storage
* Supported system integration, data security, and backend functionality


---

# 🎓 Academic Information

**Project Title:** School/College Pick-and-Drop Management System

**Degree:** Bachelor of Science in Software Engineering (BSSE)

**University:** COMSATS University Islamabad, Abbottabad Campus

**Project Type:** Final Year Project (FYP)

**Academic Session:** Fall 2025 – Spring 2026

**Department:** Department of Software Engineering

**Project Supervisor:** Dr. Abdul Nasir Khan

---

# 📄 License

This project was developed as a Final Year Project for academic purposes.

© 2026 Aiman Shabbir & Areeba Khan. All rights reserved.
