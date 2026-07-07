# 🧠 Models Directory

This directory serves as the local storage and staging area for all Large Language Model weights used by the `llm-ops` infrastructure.

## ⚠️ Important Note on Version Control

**Do not commit `.gguf` files to Git.**

Large Language Models range from 1GB to 5GB+ in size. This directory relies on a `.gitignore` rule (`*.gguf`) to prevent these massive binary files from being accidentally pushed to your remote repository.

## 📥 How to Download Models

Models are not included in the repository by default. To provision this directory, use the automated fetch script located in the `scripts/` folder. The script uses the Hugging Face `hf` CLI to securely download the optimized Q4 quantized (`Q4_K_M`) models.

Run the following command from the **root of the repository**:

# Download all configured models
```bash
./scripts/fetch-hf-models.sh ./models
```

# Download a specific model family (e.g., Qwen)
```bash
./scripts/fetch-hf-models.sh ./models qwen
```

## 📦 Supported Models Reference

The provisioning script is configured to download the following models, which have been specifically chosen and calculated to fit within an 8GB RAM host environment:

| Model | Parameters | Quantization | Max Safe Context |
| :--- | :--- | :--- | :--- |
| **Llama-3.2-1B-Instruct** | 1B | `Q4_K_M` | 64k |
| **DeepSeek-R1-Distill-Qwen-1.5B** | 1.5B | `Q4_K_M` | 64k |
| **Qwen2.5-1.5B-Instruct** | 1.5B | `Q4_K_M` | 64k |
| **Qwen2.5-Coder-3B-Instruct** | 3B | `Q4_K_M` | 32k |
| **Llama-3.2-3B-Instruct** | 3B | `Q4_K_M` | 32k |
| **Granite-3.1-3B-A800M-Instruct** | 3B | `Q4_K_M` | 32k |
| **Ministral-3-3B (Instruct & Reasoning)**| 3B | `Q4_K_M` | 32k |
| **Phi-3.5-Mini-Instruct** | 3.8B | `Q4_K_M` | 16k |
| **Qwen3.5-4B** | 4B | `Q4_K_M` | 16k |
| **Google Gemma-4 (2B & 4B)** | 2B / 4B | `Q4_K_M` | 8k (Native Limit) |
| **SmolLM3** | ~3B | `Q4_K_M` | 8k (Native Limit) |

## 💾 Storage Requirements

If you choose to download all the models listed above simultaneously, you will need approximately **25 GB to 30 GB of free disk space** dedicated to your models directory.
