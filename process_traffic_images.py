import cv2
import numpy as np
import tensorflow as tf
import os
import json

# Parameters
IMG_HEIGHT = 128
IMG_WIDTH = 128

# Dice Loss (unchanged)
def dice_loss(y_true, y_pred, smooth=1e-6):
    y_true_f = tf.keras.backend.flatten(y_true)
    y_pred_f = tf.keras.backend.flatten(y_pred)
    intersection = tf.keras.backend.sum(y_true_f * y_pred_f)
    return 1 - ((2. * intersection + smooth) / (tf.keras.backend.sum(y_true_f) + tf.keras.backend.sum(y_pred_f) + smooth))

# Load Models (unchanged)
def load_trained_model(model_path, custom_objects=None):
    return tf.keras.models.load_model(model_path, custom_objects=custom_objects)

# Preprocess Image (unchanged)
def preprocess_image(image_path):
    img = cv2.imread(image_path)
    if img is None:
        raise FileNotFoundError(f"Image not found at {image_path}")
    ycrcb = cv2.cvtColor(img, cv2.COLOR_BGR2YCrCb)
    y, cr, cb = cv2.split(ycrcb)
    clahe = cv2.createCLAHE(clipLimit=3.0, tileGridSize=(8,8))
    y = clahe.apply(y)
    enhanced_img = cv2.merge((y, cr, cb))
    img = cv2.cvtColor(enhanced_img, cv2.COLOR_YCrCb2BGR)
    img = cv2.fastNlMeansDenoisingColored(img, None, 10, 10, 7, 21)
    kernel = np.array([[0, -1, 0], [-1, 5, -1], [0, -1, 0]])
    img = cv2.filter2D(img, -1, kernel)
    img = cv2.resize(img, (IMG_WIDTH, IMG_HEIGHT))
    img = img / 255.0
    img = np.expand_dims(img, axis=0)
    return img

# Post-process Road Segmentation (unchanged)
def postprocess_road_mask(prediction):
    prediction = prediction.squeeze()
    return (prediction > 0.5).astype(np.uint8)

# Post-process Vehicle Segmentation (unchanged)
def postprocess_vehicle_mask(prediction):
    prediction = prediction.squeeze()
    return np.argmax(prediction, axis=-1)

# Extract Segmented Road (unchanged)
def extract_segmented_road(original_image, road_mask):
    mask_resized = cv2.resize(road_mask, (original_image.shape[1], original_image.shape[0]), interpolation=cv2.INTER_NEAREST)
    segmented_road = cv2.bitwise_and(original_image, original_image, mask=mask_resized.astype(np.uint8) * 255)
    return segmented_road, mask_resized

# Overlay Mask (unchanged)
def overlay_mask(image, mask, color=(255, 0, 0)):
    mask_colored = np.zeros_like(image)
    mask_colored[mask > 0] = color
    return cv2.addWeighted(image, 0.7, mask_colored, 0.3, 0)

# Process Folder of Images
def process_folder(road_model_path, vehicle_model_path, folder_path, output_json_path):
    # Load models
    road_model = load_trained_model(road_model_path)
    vehicle_model = load_trained_model(vehicle_model_path)

    # Camera mapping (updated to match subfolder names exactly)
    camera_mapping = {
        'Lý_Thái_Tổ_-_Sư_Vạn_Hạnh': 'A',
        'Ba_Tháng_Hai_-_Cao_Thắng': 'B',
        'Điện_Biên_Phủ_–_Cao_Thắng': 'C',  # Updated to use en dash
        'Ngã_sáu_Nguyễn_Tri_Phương_1': 'D',
        'Ngã_sáu_Nguyễn_Tri_Phương': 'E',
        'Lê_Đại_Hành_2_(Lê_Đại_Hành)': 'F',
        'Lý_Thái_Tổ_-_Nguyễn_Đình_Chiểu': 'G',
        'Ngã_sáu_Cộng_Hòa_1': 'H',
        'Ngã_sáu_Cộng_Hòa': 'I',
        'Điện_Biên_Phủ_-_Cách_Mạng_Tháng_Tám': 'J',
        'Công_Trường_Dân_Chủ': 'K',
        'Công_Trường_Dân_Chủ_1': 'L'
    }

    densities = {}

    # Iterate over all subfolders in the folder
    for subfolder in os.listdir(folder_path):
        subfolder_path = os.path.join(folder_path, subfolder)
        if os.path.isdir(subfolder_path):
            # Look for latest.png in the subfolder
            image_path = os.path.join(subfolder_path, 'latest.png')
            if not os.path.exists(image_path):
                print(f"Warning: latest.png not found in {subfolder}, skipping.")
                continue

            print(f"Processing {subfolder}/latest.png...")

            # Map subfolder name to camera ID (exact match)
            camera_id = camera_mapping.get(subfolder)
            if not camera_id:
                print(f"Warning: No camera mapping for {subfolder}, skipping.")
                continue

            # Read and preprocess image with proper encoding
            try:
                # Use cv2.imdecode to handle paths with special characters
                with open(image_path, 'rb') as f:
                    img_array = np.frombuffer(f.read(), np.uint8)
                    original_image = cv2.imdecode(img_array, cv2.IMREAD_COLOR)
                if original_image is None:
                    print(f"Error: Could not read image at {image_path}, skipping.")
                    continue
                original_image_rgb = cv2.cvtColor(original_image, cv2.COLOR_BGR2RGB)

                # Preprocess image (save to temp file to avoid path issues)
                temp_image_path = os.path.join(folder_path, f"temp_{camera_id}.png")
                cv2.imwrite(temp_image_path, original_image)
                img = preprocess_image(temp_image_path)
                os.remove(temp_image_path)  # Clean up temp file

                # Step 1: Road Segmentation
                road_pred = road_model.predict(img)
                road_mask = postprocess_road_mask(road_pred)

                # Step 2: Extract Segmented Road
                segmented_road, mask_resized = extract_segmented_road(original_image, road_mask)

                # Step 3: Vehicle Segmentation on Road
                segmented_road_resized = cv2.resize(segmented_road, (IMG_WIDTH, IMG_HEIGHT)) / 255.0
                segmented_road_resized = np.expand_dims(segmented_road_resized, axis=0)
                vehicle_pred = vehicle_model.predict(segmented_road_resized)
                vehicle_mask = postprocess_vehicle_mask(vehicle_pred)
                vehicle_mask_resized = cv2.resize(vehicle_mask.astype(np.uint8), 
                                                (original_image.shape[1], original_image.shape[0]), 
                                                interpolation=cv2.INTER_NEAREST)

                # Step 4: Calculate Vehicle Density (capped at 100%)
                vehicle_pixels = np.count_nonzero(vehicle_mask_resized)
                road_pixels = np.count_nonzero(mask_resized)
                vehicle_density = (vehicle_pixels / road_pixels) * 100 if road_pixels > 0 else 0
                vehicle_density = min(vehicle_density, 100.0)  # Cap at 100%

                densities[camera_id] = vehicle_density

                print(f"Camera {camera_id}: Density = {vehicle_density:.2f}%")
            except Exception as e:
                print(f"Error processing {image_path}: {e}, skipping.")

    # Save densities to JSON
    with open(output_json_path, 'w', encoding='utf-8') as f:
        json.dump(densities, f, ensure_ascii=False)
    print(f"Densities saved to {output_json_path}")

# Paths
road_model_path = "unet_road_segmentation (Better).keras"
vehicle_model_path = "unet_multi_classV1.keras"
folder_path = r"E:\playground\flutter_playground_vsc\flutter_ggmap_project\GetDensity\GetDensity\screenshots_traffic-20250409T050423Z-001\screenshots_traffic"
output_json_path = r"E:\playground\flutter_playground_vsc\flutter_ggmap_project\densities.json"

# Run
process_folder(road_model_path, vehicle_model_path, folder_path, output_json_path)