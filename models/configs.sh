# Set model Configurations
declare -A MODEL_CONFIGS
MODEL_CONFIGS=(
  # Group 1: Max Context (64k)
  ["llama-3.2-1b-instruct"]="4 5.5g 65536"
  ["deepseek-r1-distill-qwen-1.5b"]="4 5.5g 65536"
  ["qwen2.5-1.5b-instruct"]="4 5.5g 65536"

  # Group 2: Balanced Code (32k)
  ["llama-3.2-3b-instruct"]="4 5.5g 32768"
  ["qwen2.5-coder-3b-instruct"]="4 5.5g 32768"
  ["ministral-3-3b-instruct-2512"]="4 5.5g 32768"
  ["ministral-3-3b-reasoning-2512"]="4 5.5g 32768"
  ["granite-3.1-3b-a800m-instruct"]="4 5.5g 32768"

  # Group 3: Memory Heavy (16k)
  ["phi-3.5-mini-instruct"]="4 5.0g 16384"
  ["qwen3.5-4b"]="4 5.0g 16384"

  # Group 4: Hard-Capped Native Limits (8k)
  ["google_gemma-4-e2b-it"]="4 3.5g 8192"
  ["google_gemma-4-e4b-it"]="4 4.5g 8192"
  ["smollm3"]="4 3.5g 8192"
)

# Model Repository Mapping
declare -A MODEL_MAP
MODEL_MAP=(
  ["DeepSeek-R1-Distill-Qwen-1.5B-Q4_K_M.gguf"]="bartowski/DeepSeek-R1-Distill-Qwen-1.5B-GGUF"
  ["google_gemma-4-E2B-it-Q4_K_M.gguf"]="bartowski/google_gemma-4-E2B-it-GGUF"
  ["google_gemma-4-E4B-it-Q4_K_M.gguf"]="bartowski/google_gemma-4-E4B-it-GGUF"
  ["granite-3.1-3b-a800m-instruct.Q4_K_M.gguf"]="QuantFactory/granite-3.1-3b-a800m-instruct-GGUF"
  ["Llama-3.2-1B-Instruct-Q4_K_M.gguf"]="bartowski/Llama-3.2-1B-Instruct-GGUF"
  ["Llama-3.2-3B-Instruct-Q4_K_M.gguf"]="bartowski/Llama-3.2-3B-Instruct-GGUF"
  ["Ministral-3-3B-Instruct-2512-Q4_K_M.gguf"]="unsloth/Ministral-3-3B-Instruct-2512-GGUF"
  ["Ministral-3-3B-Reasoning-2512-Q4_K_M.gguf"]="unsloth/Ministral-3-3B-Reasoning-2512-GGUF"
  ["Phi-3.5-mini-instruct.Q4_K_M.gguf"]="bartowski/Phi-3.5-mini-instruct-GGUF"
  ["qwen2.5-1.5b-instruct-q4_k_m.gguf"]="Qwen/Qwen2.5-1.5B-Instruct-GGUF"
  ["Qwen2.5-Coder-3B-Instruct-Q4_K_M.gguf"]="Qwen/Qwen2.5-Coder-3B-Instruct-GGUF"
  ["Qwen3.5-4B-Q4_K_M.gguf"]="TirGun/Qwen3.5-4B-GGUF"
  ["SmolLM3-Q4_K_M.gguf"]="bartowski/SmolLM3-GGUF"
)
