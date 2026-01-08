docker run --runtime nvidia --gpus 1 \
    -v ~/.cache/huggingface:/root/.cache/huggingface \
    --env "HF_TOKEN=$HF_TOKEN" \
    -p 8001:8091 \
    --ipc=host \
    vllm/vllm-omni:v0.12.0rc1 \
    --model Tongyi-MAI/Z-Image-Turbo --port 8091



docker run --runtime nvidia --gpus 1 \
    -v ~/.cache/huggingface:/root/.cache/huggingface \
    --env "HF_TOKEN=$HF_TOKEN" \
    -p 8001:8091 \
    --ipc=host \
    vllm/vllm-omni:v0.12.0rc1 \
    --model Tongyi-MAI/Z-Image-Turbo \
    --port 8091 \
    --max-model-len 2048 \
    --max-num-seqs 32 \
    --limit-mm-per-prompt image=1 \
    --gpu-memory-utilization 0.95 \
    --num-scheduler-steps 10 \
    --enforce-eager