import sys
from PIL import Image

def resize_image(input_path, output_path, target_size=(64, 64)):
    try:
        img = Image.open(input_path)
        
        # Check current size and decide filter
        current_w, current_h = img.size
        # if current_w <= target_size[0] and current_h <= target_size[1]:
        #     print(f"Skipping {input_path}: Size {img.size} is already small enough.")
        #     return

        # Use NEAREST for upscaling (pixel art style), LANCZOS for downscaling
        resample_filter = Image.Resampling.LANCZOS
        if target_size[0] > current_w or target_size[1] > current_h:
            resample_filter = Image.Resampling.NEAREST
            
        img_resized = img.resize(target_size, resample_filter)
        img_resized.save(output_path, "PNG")
        print(f"Resized {input_path} from {img.size} to {target_size} (Filter: {resample_filter})")
        
    except Exception as e:
        print(f"Error processing {input_path}: {e}")

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: python resize_image.py input_file output_file [size]")
        sys.exit(1)
        
    input_file = sys.argv[1]
    output_file = sys.argv[2]
    
    size = 64
    if len(sys.argv) > 3:
        try:
            size = int(sys.argv[3])
        except:
            pass
            
    resize_image(input_file, output_file, (size, size))
