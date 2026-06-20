import sys
from PIL import Image

def make_transparent(input_path, output_path, tolerance=10):
    try:
        img = Image.open(input_path)
        img = img.convert("RGBA")
        datas = img.getdata()
        width, height = img.size
        
        # Get background colors from 4 corners to handle checkerboards
        corners = [
            (0, 0),
            (width - 1, 0),
            (0, height - 1),
            (width - 1, height - 1)
        ]
        
        bg_colors = []
        for x, y in corners:
            idx = y * width + x
            if idx < len(datas):
                c = datas[idx]
                is_new = True
                for existing in bg_colors:
                    if (abs(existing[0] - c[0]) <= tolerance and
                        abs(existing[1] - c[1]) <= tolerance and
                        abs(existing[2] - c[2]) <= tolerance):
                        is_new = False
                        break
                if is_new:
                    bg_colors.append(c)
        
        print(f"Detected background colors: {bg_colors}")

        newData = []
        for item in datas:
            # Check if pixel matches ANY background color
            is_bg = False
            for bg in bg_colors:
                if (abs(item[0] - bg[0]) <= tolerance and 
                    abs(item[1] - bg[1]) <= tolerance and 
                    abs(item[2] - bg[2]) <= tolerance):
                    is_bg = True
                    break
            
            if is_bg:
                newData.append((255, 255, 255, 0)) # Transparent
            else:
                newData.append(item)
        
        img.putdata(newData)
        img.save(output_path, "PNG")
        print(f"Successfully converted {input_path} to transparent {output_path}")
        
    except Exception as e:
        print(f"Error: {e}")

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: python make_transparent.py input_file output_file [tolerance] [r,g,b]")
        sys.exit(1)
        
    input_file = sys.argv[1]
    output_file = sys.argv[2]
    tol = 30
    target_bg = None
    
    if len(sys.argv) > 3:
        try:
            tol = int(sys.argv[3])
        except ValueError:
            pass # Use default

    if len(sys.argv) > 4:
        try:
            parts = sys.argv[4].split(',')
            if len(parts) == 3:
                target_bg = (int(parts[0]), int(parts[1]), int(parts[2]))
                print(f"Targeting specific background color: {target_bg}")
        except Exception as e:
            print(f"Error parsing color: {e}")

    try:
        img = Image.open(input_file)
        img = img.convert("RGBA")
        datas = img.getdata()
        width, height = img.size
        
        bg_colors = []
        
        if target_bg:
            bg_colors.append(target_bg)
        else:
            # Auto-detect from corners
            corners = [
                (0, 0),
                (width - 1, 0),
                (0, height - 1),
                (width - 1, height - 1)
            ]
            
            for x, y in corners:
                idx = y * width + x
                if idx < len(datas):
                    c = datas[idx][:3] # Ignore alpha for detection
                    is_new = True
                    for existing in bg_colors:
                        if (abs(existing[0] - c[0]) <= tol and
                            abs(existing[1] - c[1]) <= tol and
                            abs(existing[2] - c[2]) <= tol):
                            is_new = False
                            break
                    if is_new:
                        bg_colors.append(c)
            
        print(f"Background detection/target: {bg_colors}")

        newData = []
        for item in datas:
            # Check if pixel matches ANY background color
            is_bg = False
            for bg in bg_colors:
                if (abs(item[0] - bg[0]) <= tol and 
                    abs(item[1] - bg[1]) <= tol and 
                    abs(item[2] - bg[2]) <= tol):
                    is_bg = True
                    break
            
            if is_bg:
                newData.append((255, 255, 255, 0)) # Transparent
            else:
                newData.append(item)
        
        # --- Noise Removal (Despeckle) ---
        def remove_speckles(data, w, h, passes=2):
            # Process strictly on the list data
            # 0=R, 1=G, 2=B, 3=A. If len is 3, no Alpha. Assume RGBA input.
            current_data = list(data)
            
            for p in range(passes):
                cleaned_data = list(current_data)
                noise_removed = 0
                
                for y in range(h):
                    for x in range(w):
                        idx = y * w + x
                        pixel = current_data[idx]
                        
                        # Apply only to non-transparent pixels
                        if len(pixel) == 4 and pixel[3] == 0:
                            continue
                            
                        # Check 8 neighbors
                        neighbors = 0
                        transparent_neighbors = 0
                        
                        for dy in [-1, 0, 1]:
                            for dx in [-1, 0, 1]:
                                if dx == 0 and dy == 0: continue
                                
                                nx, ny = x + dx, y + dy
                                if 0 <= nx < w and 0 <= ny < h:
                                    neighbors += 1
                                    n_idx = ny * w + nx
                                    neighbor_pixel = current_data[n_idx]
                                    # Check if neighbor is transparent
                                    if len(neighbor_pixel) == 4 and neighbor_pixel[3] == 0:
                                        transparent_neighbors += 1
                        
                        # If almost all surrounding pixels are transparent, remove this one
                        # Threshold: if 7 out of 8 neighbors are transparent -> remove
                        # (Adjust as needed. >= neighbors - 1 allows for single sticking out pixels)
                        if neighbors > 0 and transparent_neighbors >= neighbors - 1:
                            cleaned_data[idx] = (255, 255, 255, 0)
                            noise_removed += 1
                            
                print(f"  Pass {p+1}: Removed {noise_removed} speckles")
                current_data = cleaned_data
                if noise_removed == 0:
                    break
            return current_data

        print("Cleaning up noise...")
        newData = remove_speckles(newData, width, height)
        
        img.putdata(newData)
        
        # --- Resize ---
        # Resize to a smaller resolution (default 64x64 for pixel art style)
        # Keeps file size small and consistent with game assets
        target_size = (64, 64)
        if len(sys.argv) > 5:
            try:
                s = int(sys.argv[5])
                target_size = (s, s)
            except:
                pass

        # Using Nearest Neighbor to keep pixel art look if downsizing significantly
        # Or LANCZOS for smoother downscaling from high-res AI images
        # Since source is 1024x1024 AI "pixel art", simple resizing might look blurry.
        # But let's try standard high-quality downsampling first.
        img = img.resize(target_size, Image.Resampling.LANCZOS)
        print(f"Resized image from {width}x{height} to {target_size}")
        
        img.save(output_file, "PNG")
        print(f"Successfully converted {input_file} to {output_file}")
        
    except Exception as e:
        print(f"Error processing {input_file}: {e}")
        import traceback
        traceback.print_exc()
