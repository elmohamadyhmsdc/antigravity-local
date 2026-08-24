# Reface: Advanced Face Swapping Documentation

**Reface** is a powerful face-swapping module within Antigravity Local that allows users to replace faces in images and videos with high fidelity. Unlike simple face swappers, Reface uses **Facesets** and **Angle Matching** to ensure that the replaced face matches the pose and lighting of the target, resulting in more realistic edits.

---

## 🏗️ Core Concepts

### 1. Facesets
A **Faceset** is a collection of face data extracted from one person. Instead of using a single photo as a source, Reface builds a database of the person's face from multiple angles (front, left, right, up, down).
*   **Why use it?** A single photo might look good for a frontal swap but fails when the target is looking sideways. A Faceset provides the engine with the correct angle to use for every frame.
*   **Storage:** Facesets are saved permanently in `antigravity-local/facesets/` and can be reused.

### 2. Angle Matching
When enabled, the engine calculates the **Yaw, Pitch, and Roll** of the face in the target image. It then searches the selected Faceset for the source face that has the closest matching angle.
*   **Result:** The swapped face looks naturally positioned, preserving the 3D geometry of the scene.

### 3. Face Enhancement
The system includes a post-processing enhancer that:
*   Upscales the result (2x or 4x).
*   Applies sharpening and denoising.
*   Performs color correction to blend the skin tones with the target environment.

---

## 🚀 How to Use

The Reface interface is divided into three main steps in the Dashboard.

### Step 1: Source Media (Who do you want to be?)
You have two options for selecting the "Source" face:

#### Option A: Quick Upload
1.  Go to the **Reface** tab.
2.  Under **Step 1: Source Media**, select the **📤 Upload New** tab.
3.  Upload one or more photos/videos of the person you want to insert.
    *   *Tip: Uploading a video of the person turning their head is the best way to capture all angles.*

#### Option B: Use a Faceset (Recommended)
1.  Under **Step 1**, select the **Use Faceset** tab.
2.  Choose a pre-built faceset from the dropdown.
3.  Click **✅ Use This Faceset**.
    *   *To create a new Faceset, go to the "Build & Manage Facesets" tab at the bottom of the page.*

### Step 2: Target Media (Where do you want to put the face?)
1.  Under **Step 2: Target Media**, upload the image or video that contains the face you want to replace.
2.  **Detection**: Once uploaded, click **🔍 Detect Faces**.
3.  **Selection**: The system will show all faces found in the target.
    *   **Select Specific Faces**: Check the boxes of the faces you want to swap.
    *   **Leave Empty**: If you don't select any, the system will swap **ALL** faces found.

### Step 3: Options & Execute
Configure your final settings:

*   **Output Quality**: Select `1x` (Fast), `2x` (Standard), or `4x` (High Detail).
*   **Use Angle Matching**: Keep this **Checked** for best results. Unchecking it forces the system to use the first available source face, which may look unnatural.
*   **Run in Background**: 
    *   **Checked**: Submits the job to a queue. You can close the tab and check status later. **Recommended for Videos.**
    *   **Unchecked**: Runs continuously in the browser. You must keep the tab open. Good for single images.

Click **🚀 Swap Faces** (or **Start Background Job**) to begin.

---

## ⚙️ Background Jobs & Queue

For video processing, operations can take time. The **Background Jobs** tab allows you to manage this:

*   **Monitor Progress**: See real-time progress bars for running jobs.
*   **Queue System**: If a job is running, new jobs are queued and will start automatically when the worker is free.
*   **Manage**: You can **Pause**, **Resume**, or **Delete** jobs.
*   **Download**: Once finished, preview the video and download the result directly.

---

## 🛠️ Technical Details

*   **Engine**: `reface_engine.py` using `insightface` and `onnxruntime`.
*   **Model**: Uses `inswapper_128.onnx` for the core swap.
*   **Acceleration**: Automatically detects CUDA (NVIDIA GPU). If not found, falls back to CPU (slower).
*   **Video Formats**: 
    *   Input: `.mp4`, `.avi`, `.mov`, `.mkv`
    *   Output: `.mp4` (H.264 for browser compatibility).

### Directory Structure
*   `reface_uploads/`: Temporary storage for current session uploads.
*   `reface_output/`: Stores the final swapped images and videos.
*   `facesets/`: Stores serialized Faceset data (`.pkl`) and the source images used to build them.

---

## ❓ Troubleshooting

| Issue | Cause | Solution |
| :--- | :--- | :--- |
| **"Inswapper model not loaded"** | The `.onnx` model file is missing. | Download `inswapper_128.onnx` and place it in the `models/` folder. |
| **Swapped face looks flat/weird** | Source face angle doesn't match target. | Ensure you are using a detailed **Faceset** or upload a source video showing more angles. |
| **No faces detected** | Image resolution too low or face obscured. | Use higher resolution media or try a clearer frame. |
| **Slow processing** | Running on CPU. | Ensure CUDA is installed and `onnxruntime-gpu` is active for GPU acceleration. |
