#!/bin/bash

# Bash script to process all objects from 1 to 21 using 2DGaussian training and rendering
# This script runs training and rendering for both segmented and surface variants

# Base path where all object directories are located
BASE_PATH="/home/stefan/Downloads/dataset_test_real_labor"

# Set to true or false to enable/disable processing of each variant
PROCESS_SURFACE=true
PROCESS_SEGMENTED=false

# Choose the parent folder for variants: 'mast3r-sfm' or 'vggt'
VARIANT_PARENT="mast3r-sfm"  # or 'vggt'

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
    echo "  Running: python $TRAIN_ALPHA_SCRIPT --source_path $variant_path --model_path $model_output_path"
    if ! python "$TRAIN_ALPHA_SCRIPT" --source_path "$variant_path" --model_path "$model_output_path"; then
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
