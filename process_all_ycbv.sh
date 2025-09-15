#!/bin/bash

# Bash script to process all objects from 1 to 21 using 2DGaussian training and rendering
# This script runs training and rendering for both segmented and surface variants

# Base path where all object directories are located
BASE_PATH="/home/stefan/Projects/Grounded-SAM-2-zeroshop/dataset"

# Set to true or false to enable/disable processing of each variant
PROCESS_SURFACE=true
PROCESS_SEGMENTED=false
POSTPROCESSING=true

# Set Rendering Resolution
RESOLUTION=400 # 1600 for best

# Choose the parent folder for variants: 'mast3r-sfm' or 'vggt'
VARIANT_PARENT="mast3r-sfm"  # or 'mast3r-sfm'

# Path to the training and rendering scripts
TRAIN_ALPHA_SCRIPT="train_alpha.py"
RENDER_SCRIPT="render.py"

# Check if scripts exist
if [ ! -f "$TRAIN_ALPHA_SCRIPT" ]; then
    echo "Error: Training script not found at $TRAIN_ALPHA_SCRIPT"
    exit 1
fi

if [ ! -f "$RENDER_SCRIPT" ]; then
    echo "Error: Render script not found at $RENDER_SCRIPT"
    exit 1
fi

# Check if the base path exists
if [ ! -d "$BASE_PATH" ]; then
    echo "Error: Base path not found at $BASE_PATH"
    exit 1
fi

echo "Starting 2DGS processing for objects 1 to 21..."
echo "Base path: $BASE_PATH"
echo "Training script: $TRAIN_ALPHA_SCRIPT"
echo "Rendering script: $RENDER_SCRIPT"
echo "========================================"

# Counter for successful and failed processing
success_count=0
failed_count=0
failed_objects=()

# Function to process a single variant (segmented or surface)
process_variant() {
    local obj_path="$1"
    local variant="$2"
    local obj_num="$3"

    local variant_path="$obj_path/train_pbr/$VARIANT_PARENT/$variant"

    echo "  Processing $variant variant..."
    echo "  Variant path: $variant_path"

    # Check if the variant directory exists
    if [ ! -d "$variant_path" ]; then
        echo "  Warning: $variant directory not found: $variant_path"
        return 1
    fi

    # Step 1: Training

    local model_output_path="$variant_path/2DGS_output"
    echo "  Step 1: Training $variant..."
    echo "  Running: python $TRAIN_ALPHA_SCRIPT --source_path $variant_path --model_path $model_output_path --resolution $RESOLUTION"
    if ! python "$TRAIN_ALPHA_SCRIPT" --source_path "$variant_path" --model_path "$model_output_path" --resolution $RESOLUTION; then
        echo "  ✗ Failed to train $variant for obj_$obj_num"
        return 1
    fi

    echo "  ✓ Training completed for $variant"

    # Step 2: Rendering
    echo "  Step 2: Rendering for $variant..."
    echo "  Running: python $RENDER_SCRIPT --source_path $variant_path --model_path $model_output_path"
    if ! python "$RENDER_SCRIPT" --source_path "$variant_path" --model_path "$model_output_path"; then
        echo "  ✗ Failed to render for $variant of obj_$obj_num"
        return 1
    fi
    echo "  ✓ Rendering completed for $variant"
    
    # Post-processing mesh if enabled
    if [ "$POSTPROCESSING" = true ]; then
        echo "  Step 3: Post-processing mesh for $variant..."

        # Activate pymeshlab environment
        source ~/miniconda3/etc/profile.d/conda.sh
        conda activate postprocess

        bundler_file="$variant_path/images/scene.bundle.out"
        bundler_txt="$variant_path/images/scene.list.txt"
        object_info_json="$obj_path/scene/output/object_info.json"

        # Find mesh file in 2DGS_output directory
        mesh_dir="$variant_path/2DGS_output/train/ours_30000"
        mesh_file=""
        if [ -d "$mesh_dir" ]; then
            # Prefer fuse_post.ply, fall back to fuse.ply
            if [ -f "$mesh_dir/fuse_post.ply" ]; then
                mesh_file="$mesh_dir/fuse_post.ply"
            elif [ -f "$mesh_dir/fuse.ply" ]; then
                mesh_file="$mesh_dir/fuse.ply"
            fi
        fi

        if [ -z "$mesh_file" ]; then
            echo "  Warning: No mesh file found for post-processing in $mesh_dir"
            return 1
        fi

        if [ ! -f "$bundler_file" ] || [ ! -f "$bundler_txt" ]; then
            echo "  Warning: Bundler files not found for post-processing."
            return 1
        fi

        if [ ! -f "$object_info_json" ]; then
            echo "  Warning: object_info.json not found for post-processing."
            return 1
        fi

        echo "  Running: python postprocess.py --mesh \"$mesh_file\" --bundler \"$bundler_file\" --bundler_txt \"$bundler_txt\" --object_info_json \"$object_info_json\""
        if ! python postprocess.py --mesh "$mesh_file" --bundler "$bundler_file" --bundler_txt "$bundler_txt" --object_info_json "$object_info_json" --texture; then
            echo "  ✗ Failed to post-process mesh for $variant of obj_$obj_num"
            return 1
        fi

        echo "  ✓ Post-processing completed for $variant"

        # Return to original environment
        conda activate surfel_splatting
    fi
    
    return 0
}

# Loop through objects 1 to 21
for i in {1..21}; do
    # Format the object number with leading zeros (6 digits)
    obj_num=$(printf "%06d" $i)
    obj_path="$BASE_PATH/obj_$obj_num"

    echo ""
    echo "Processing object $i (obj_$obj_num)..."
    echo "Object path: $obj_path"

    # Check if the object directory exists
    if [ ! -d "$obj_path" ]; then
        echo "Warning: Object directory not found: $obj_path"
        echo "Skipping obj_$obj_num"
        ((failed_count++))
        failed_objects+=("obj_$obj_num (directory not found)")
        continue
    fi

    # Track success for this object
    obj_success=true


    # Process surface variant if enabled
    if [ "$PROCESS_SURFACE" = true ]; then
        echo ""
        echo "--- Processing SURFACE variant for obj_$obj_num ---"
        if ! process_variant "$obj_path" "surface" "$obj_num"; then
            echo "Failed to process surface variant for obj_$obj_num"
            obj_success=false
        fi
    else
        echo "Skipping SURFACE variant for obj_$obj_num (PROCESS_SURFACE=false)"
    fi

    # Process segmented variant if enabled
    if [ "$PROCESS_SEGMENTED" = true ]; then
        echo ""
        echo "--- Processing SEGMENTED variant for obj_$obj_num ---"
        if ! process_variant "$obj_path" "segmented" "$obj_num"; then
            echo "Failed to process segmented variant for obj_$obj_num"
            obj_success=false
        fi
    else
        echo "Skipping SEGMENTED variant for obj_$obj_num (PROCESS_SEGMENTED=false)"
    fi

    # Update counters
    if [ "$obj_success" = true ]; then
        echo "✓ Successfully processed all variants for obj_$obj_num"
        ((success_count++))
    else
        echo "✗ Failed to process one or more variants for obj_$obj_num"
        ((failed_count++))
        failed_objects+=("obj_$obj_num")
    fi

    echo "========================================"
done

echo ""
echo "========================================"
echo "2DGAUSSIAN PROCESSING COMPLETE"
echo "========================================"
echo "Total objects processed: $((success_count + failed_count))"
echo "Successful: $success_count"
echo "Failed: $failed_count"

if [ $failed_count -gt 0 ]; then
    echo ""
    echo "Failed objects:"
    for failed_obj in "${failed_objects[@]}"; do
        echo "  - $failed_obj"
    done
fi

echo ""
if [ $failed_count -eq 0 ]; then
    echo "All objects processed successfully!"
    echo "Training and mesh extraction completed for enabled variants."
    echo "Results are saved in the respective model paths under 2DGS_output:"
    echo "  - {object}/train_pbr/$VARIANT_PARENT/segmented/"
    echo "  - {object}/train_pbr/$VARIANT_PARENT/surface/"
    exit 0
else
    echo "Some objects failed to process. Check the logs above for details."
    exit 1
fi
