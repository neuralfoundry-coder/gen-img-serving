# create conda env and activate
conda deactivate
conda create -n vllm-omni python=3.12 -y
conda activate vllm-omni

# create python env
uv venv --python 3.12 --seed
source .venv/bin/activate

# installation of vLLM and vLLM-Omni
uv pip install vllm==0.12.0 --torch-backend=auto
uv pip install vllm-omni


