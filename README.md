# AI-Powered Virtual White Cane

**Candidate:** Tudor-Sorin Ciutacu\
**Supervisors:** As. prof. dr. eng. Cosmin Cernăzanu-Glăvan, Drd. eng. Andrei-Ștefan Bulzan\
**Academic Year:** 2024-2025 

_Computers and Information Technology, AC, UPT_

---

## 📑 Project Description

The **AI-Powered Virtual White Cane** is a mobile application designed to assist visually impaired users by detecting obstacles using real-time object detection, semantic segmentation, and LiDAR-based distance estimation. The app runs fully on-device, providing haptic and audio feedback at three levels of intensity, helping users navigate safely.

---

## 🔗 Repository Address

The project can be accessed at the following GitLab address of the repository:

> [https://gitlab.upt.ro/tudor.ciutacu/virtual-cane](https://gitlab.upt.ro/tudor.ciutacu/virtual-cane)

---

## 🧩 Technology Stack

* **Language:** Swift 6
* **Frameworks:** CoreML, Vision, ARKit, RealityKit, SwiftUI
* **IDE:** Xcode 14+
* **Models:** [YOLOv11](https://docs.ultralytics.com/models/yolo11/) (Object Detection), [DETR ResNet50](https://developer.apple.com/machine-learning/models/#:~:text=DETR%20Resnet50%20Semantic%20Segmentation) (Semantic Segmentation)
* **HW:** LiDAR scanner (Distance Measuring), Taptic Motor (Haptic Feedback)

---

## 📁 Project Structure

```
📁 VirtualCane/
 ├── 📄 VirtualCane.xcodeproj
 ├── 📁 VirtualCane/                # Main source code
 │   ├── AppDelegate.swift
 │   ├── ARSessionHandler.swift
 │   ├── ARViewContainer.swift
 │   ├── Assets.xcassets/           # Project assets
 │   ├── ContentView.swift
 │   ├── CoreImageExtensions.swift
 │   ├── Info.plist                 # Configuration file
 │   ├── models/                    # CoreML models
 │   ├── Preview Content/           # SwiftUI preview assets
 │   ├── SegmentationModelHelper.swift
 │   ├── SpeechCommandRecognizer.swift
 ├── 📁 VirtualCaneTests/           # Unit tests
 └── 📁 VirtualCaneUITests/         # UI tests
```

---

## 📦 Deliverables

* Full Swift source code (without compiled binaries):
* `models/` folder containing the required models
* Xcode specific project files
* Configuration files, e.g. `Info.plist`, `VirtualCane.xcodeproj`, etc.
* README file including:
  * Project description.
  * Build steps.
  * Installation and usage guide.

---

## ⚙️ Build Steps

> **Note**\
> In order to build the project a system running macOS is required. Currently it is the only platform supported.

1. **Install Dependencies**

   * Ensure you have **Xcode 14.0+** installed.
   * The project uses **Swift**, **CoreML**, **Vision**, and **ARKit** frameworks — no extra packages are required apart from the bundled CoreML models.
   * If additional models are added, they must be copied to the project inside the `models/` folder.

2. **Clone the Repository**

   ```bash
   git clone https://gitlab.upt.ro/tudor.ciutacu/virtual-cane.git
   ```

3. **Open in Xcode**

   Open the project’s `.xcodeproj` file by *double-clicking* it.

4. **Code signing**

    > Make sure to have a valid Apple ID which is required for signing the app.
    - Open the project settings and navigate to *Signing & Capabilities*.
    - Select the appropriate development team.

5. **Build**

   * Click `Product` > `Build` or use the shortcut `Cmd+B`.

---

## 🚀 Installation & Launch

1. Connect your **iPhone** to your development machine (macOS system).

2. In Xcode:

   * Select your physical device from the target list.

3. Click `Product` > `Run` (`Cmd+R`).

4. **App Certificates**
   * Navigate to Settings > General > VPN & Device Management > *DEVELOPER APP* > Trust App

5. The app will be installed and started  automatically upon running and trusting it.

6. **App Permissions:**

   * Allow camera access.

7. **How to Use:**

   * Hold the phone at waist or chest level.
   * The app will display bounding boxes, depth heatmap and distance information in real-time.
   * The haptic and audio feedback will trigger according to obstacle proximity.

> **Note**\
> The app will be available for 7 days on a free developer account. After the period of 7 days expires the app will need to be re-deployed on device.
---

## ✅ Requirements

* macOS (version **14** or later) with **Xcode 14+**
* **iPhone 12 Pro or newer** with LiDAR sensor
* **iOS 17.0+** with ARKit 6 support


---

## 📌 Notes

* The repository does **not** contain any compiled binaries.
* This version is tested on **iOS 17+** with LiDAR-capable iPhones.
* All processing is done on-device for privacy and lower latency.
* Currently supported platform is **iOS** for now, future work includes expanding support for **Android** devices.

---

## 📜 License

This project is licensed under the **MIT License**. See the [LICENSE](LICENSE) file for details.

Developed as a Bachelors Thesis Final Project at Politehnica University of Timișoara.

