# GRPO Training Script Implementation Plan

## Overview

Implement a modular GRPO (Group Relative Policy Optimization) training framework with pluggable variants:
1. **Baseline GRPO**: Standard implementation with multiple full generations per prompt
2. **STORPO**: Novel variant that regenerates from reasoning step boundaries

**Design Goal**: Easy to add new GRPO variants by implementing a simple interface.

**Stack**: Qwen 2.5 0.5B/1.5B, vLLM for rollouts, custom PyTorch training, GSM8K dataset

**Multi-GPU Setup**:
- GPU 0: vLLM for rollout generation
- GPU 1: Training model + reference model

---

## Project Structure

```
grpo_training/
├── configs/
│   ├── baseline.yaml            # Baseline GRPO config
│   └── storpo.yaml              # STORPO config
├── src/
│   ├── __init__.py
│   ├── config.py                # Configuration dataclasses
│   ├── data/
│   │   ├── __init__.py
│   │   └── gsm8k_loader.py      # GSM8K dataset loading
│   ├── generation/
│   │   ├── __init__.py
│   │   ├── vllm_generator.py    # vLLM rollout wrapper
│   │   ├── mock_generator.py    # Mock for local testing
│   │   └── rollout_buffer.py    # Completion storage
│   ├── rewards/
│   │   ├── __init__.py
│   │   └── gsm8k_reward.py      # Binary correctness reward
│   ├── variants/                # GRPO variants (pluggable)
│   │   ├── __init__.py
│   │   ├── base.py              # Abstract base class for variants
│   │   ├── baseline.py          # Standard GRPO
│   │   └── storpo.py            # Step-based rollout variant
│   └── training/
│       ├── __init__.py
│       ├── grpo_loss.py         # GRPO loss computation
│       └── trainer.py           # Main training loop
├── tests/                       # Unit tests (run locally)
│   ├── __init__.py
│   ├── test_storpo.py           # STORPO splitting tests
│   ├── test_rewards.py          # Reward extraction tests
│   ├── test_rollout_buffer.py   # Advantage computation tests
│   └── test_config.py           # Config loading tests
├── scripts/
│   └── train.py                 # Entry point
└── requirements.txt
```

---

## Implementation Steps

### Step 1: Create Project Structure and Dependencies

Create `requirements.txt`:
```
# Core (needed for both local and cloud)
torch>=2.1.0
transformers>=4.36.0
peft>=0.7.0
datasets>=2.16.0
pyyaml>=6.0
tqdm>=4.66.0
pytest>=7.0.0

# Cloud only (skip on M1 Mac)
# vllm>=0.2.7       # Uncomment on cloud GPU
# bitsandbytes>=0.42.0  # Uncomment on cloud GPU
```

For local M1 testing, install with: `pip install -r requirements.txt`
For cloud, uncomment vllm and bitsandbytes lines.

Create all directories and `__init__.py` files.

### Step 2: Configuration Module (`src/config.py`)

Define dataclasses for:
- `ModelConfig`: model_name, dtype, LoRA settings
- `GenerationConfig`: max lengths, temperature, vLLM memory utilization
- `GRPOConfig`: group_size, clip_epsilon, kl_beta, mode (baseline/reasoning_step), completions_per_step
- `TrainingConfig`: learning_rate, batch_size, gradient_accumulation, max_steps
- `Config`: top-level combining all configs, with YAML loading

### Step 3: GSM8K Data Loader (`src/data/gsm8k_loader.py`)

- Load GSM8K from HuggingFace datasets
- Extract question and answer (after `####`)
- Format prompts with chat template
- Return list of `{"question": str, "answer": str}`

### Step 4: vLLM Generator (`src/generation/vllm_generator.py`)

Key class `VLLMGenerator`:
- `__init__(model_name, device="cuda:0")`: Initialize vLLM on dedicated GPU
- `generate(prompts, sampling_params, num_completions)`: Generate completions
- `generate_continuation(prefixes, sampling_params, num_completions)`: For continuation-based variants
- `sync_weights(named_parameters)`: **In-place weight update** using `model.load_weights()`

```python
import os
os.environ["VLLM_USE_V1"] = "0"  # Use v0 engine for weight sync support

class VLLMGenerator:
    def __init__(self, model_name, device="cuda:0"):
        from vllm import LLM
        self.device = device
        self.llm = LLM(
            model=model_name,
            tensor_parallel_size=1,
            gpu_memory_utilization=0.9,
            device=device,
        )

    def sync_weights(self, named_parameters):
        """Sync weights from training model to vLLM in-place (v0 API)."""
        weights = [(name, param.data.to(self.device))
                   for name, param in named_parameters]
        model = self.llm.llm_engine.model_executor.driver_worker.model_runner.model
        model.load_weights(weights)
```

**Note**: Requires `VLLM_USE_V1=0` for weight sync to work. See [vLLM issue #16607](https://github.com/vllm-project/vllm/issues/16607).

### Step 5: Variant Base Class (`src/variants/base.py`)

Abstract base class for GRPO variants - **key for extensibility**:

```python
from abc import ABC, abstractmethod

class GRPOVariant(ABC):
    """Base class for GRPO variants. Implement this to add new variants."""

    @property
    @abstractmethod
    def name(self) -> str:
        """Unique name for this variant."""
        pass

    @abstractmethod
    def generate_rollouts(
        self,
        generator: VLLMGenerator,
        prompts: List[str],
        ground_truths: List[str],
        reward_fn: RewardFunction,
        config: Config,
    ) -> RolloutBuffer:
        """
        Generate rollouts for this variant.

        This is where the variant-specific logic lives:
        - How many completions to generate
        - Whether to split/regenerate
        - How to group completions for advantage calculation

        Returns a RolloutBuffer with all samples and computed advantages.
        """
        pass
```

### Step 6: Baseline Variant (`src/variants/baseline.py`)

```python
class BaselineGRPO(GRPOVariant):
    name = "baseline"

    def generate_rollouts(self, generator, prompts, ground_truths, reward_fn, config):
        # Generate G completions per prompt
        # Compute rewards
        # Group by prompt, compute advantages
        # Return buffer
```

### Step 7: STORPO Variant (`src/variants/storpo.py`)

```python
class STORPO(GRPOVariant):
    """Step-based rollout variant - regenerates from reasoning step boundaries."""
    name = "storpo"

    def __init__(self, config):
        self.delimiters = config.storpo.delimiters  # [". ", ".\n"]
        self.completions_per_step = config.storpo.completions_per_step
        self.min_steps = config.storpo.min_steps
        self.max_steps = config.storpo.max_steps

    def split_completion(self, completion: str) -> List[int]:
        """Find sentence boundaries (reasoning steps)."""
        # Regex: (?<![0-9])\.(?:\s+|\n+)(?=[A-Z0-9])
        pass

    def generate_rollouts(self, generator, prompts, ground_truths, reward_fn, config):
        # 1. Generate 1 initial completion per prompt
        # 2. Split each into reasoning steps
        # 3. Regenerate K continuations from each step boundary
        # 4. All completions (original + regenerations) form one advantage group
        # Return buffer
```

**To add a new variant**: Create a new file in `src/variants/`, implement `GRPOVariant`, register in `__init__.py`.

### Step 8: Rollout Buffer (`src/generation/rollout_buffer.py`)

Classes:
- `RolloutSample`: prompt, completion, tokens, reward, continuation metadata
- `RolloutGroup`: samples for one prompt, computes advantages
- `RolloutBuffer`: stores all groups, provides training batch

Advantage computation (per-group):
```python
advantages = (rewards - mean(rewards)) / (std(rewards) + eps)
```

### Step 9: GSM8K Reward (`src/rewards/gsm8k_reward.py`)

Class `GSM8KReward`:
- Extract answer using patterns: `#### <num>`, `\boxed{<num>}`, `The answer is <num>`
- Normalize to float (handle commas, decimals)
- Return 1.0 for correct, 0.0 for incorrect
- Optional format bonus (0.1) if answer extracted but wrong

### Step 10: GRPO Loss (`src/training/grpo_loss.py`)

**Loss formula:**
```
L = -min(ratio * A, clip(ratio, 1-ε, 1+ε) * A) + β * KL
```

Where:
- `ratio = π_θ(token) / π_old(token)` (probability ratios)
- `A` = normalized advantage (constant per completion)
- `KL ≈ exp(log_ref - log_π) - (log_ref - log_π) - 1`

Function `compute_log_probs(model, input_ids, attention_mask, labels)`:
- Forward pass → logits → log_softmax → gather token probs

Class `GRPOLoss`:
- Takes current/old/ref log probs, advantages, completion mask
- Returns loss + metrics (kl, ratio, clip_fraction)

### Step 11: Main Trainer (`src/training/trainer.py`)

Class `GRPOTrainer`:

**Setup:**
- Load tokenizer
- Initialize vLLM generator on GPU 0
- Load training model with LoRA on GPU 1
- Load frozen reference model on GPU 1
- Setup AdamW optimizer
- **Load the selected variant** (from registry)

**Training loop (variant-agnostic):**
```python
# Variant registry
VARIANTS = {
    "baseline": BaselineGRPO,
    "storpo": STORPO,
}

class GRPOTrainer:
    def __init__(self, config):
        self.variant = VARIANTS[config.variant](config)
        # ... setup models

    def train(self, dataset):
        for step in range(max_steps):
            prompts, answers = sample_batch(dataset)

            # Variant handles all rollout logic
            rollout_buffer = self.variant.generate_rollouts(
                self.generator, prompts, answers, self.reward_fn, self.config
            )

            # Training is the same for all variants
            metrics = self.train_step(rollout_buffer)

            if step % sync_interval == 0:
                self.sync_weights_to_vllm()

            self.log_and_checkpoint(step, metrics)
```

**Train step (shared by all variants):**
1. Get batch from rollout buffer
2. Tokenize prompts + completions
3. Create completion mask (only completion tokens, not prompt)
4. Compute log probs on GPU 1: current, old (detached current), reference
5. Compute GRPO loss
6. Backward + gradient clipping + optimizer step

### Step 12: Training Script (`scripts/train.py`)

```python
def main():
    config = Config.from_yaml(args.config)

    # Override variant if specified
    if args.variant:
        config.variant = args.variant

    dataset = load_gsm8k()
    trainer = GRPOTrainer(config)
    trainer.setup()
    trainer.train(dataset)

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", default="configs/config.yaml")
    parser.add_argument("--variant", choices=["baseline", "storpo"])
    main()
```

---

## Key Design Decisions

### Multi-GPU Architecture

Simple GPU separation:
- **GPU 0**: vLLM for rollout generation (stays loaded)
- **GPU 1**: Training model + reference model

Weights are synced from training model to vLLM periodically (every N steps). This avoids complex save/reload cycles.

### Weight Synchronization (In-Place)

Based on [verl's implementation](https://github.com/volcengine/verl/blob/main/verl/workers/rollout/vllm_rollout/vllm_rollout.py) and [vLLM issue #16607](https://github.com/vllm-project/vllm/issues/16607):

**Important**: vLLM v1 changed the API path for weight updates. We need version-aware code:

```python
def sync_weights_to_vllm(self, training_model):
    """Sync training model weights to vLLM without engine restart."""
    weights = [(name, param.data.to(self.device))
               for name, param in training_model.named_parameters()]

    # vLLM v0 path (VLLM_USE_V1=0)
    try:
        model = self.llm.llm_engine.model_executor.driver_worker.model_runner.model
        model.load_weights(weights)
    except AttributeError:
        # vLLM v1 path - API changed, may need different approach
        # See: https://github.com/vllm-project/vllm/issues/16434
        raise NotImplementedError(
            "vLLM v1 weight sync not yet supported. "
            "Set VLLM_USE_V1=0 or use vLLM < 0.8"
        )
```

**Recommendation**: Use vLLM with `VLLM_USE_V1=0` environment variable for now, as v1 multiprocessing weight updates are still being stabilized. See [vLLM blog on RLHF](https://blog.vllm.ai/2025/04/23/openrlhf-vllm.html) for latest updates.

### STORPO Variant Specifics

- Initial completion + all regenerations form ONE advantage group
- Regenerations share prefix with original → only train on tokens after regeneration point
- More completions per prompt but smaller batch size (gradient accumulation compensates)

### Adding New Variants

1. Create `src/variants/my_variant.py`
2. Implement `GRPOVariant` base class
3. Register in `src/variants/__init__.py`
4. Add variant-specific config to `config.yaml`

Example new variant ideas:
- Token-level GRPO (regenerate from each token)
- Branching GRPO (tree of continuations)
- Reward-weighted GRPO (sample more from high-reward prefixes)

### Old Policy Log Probs

For simplicity, use detached current policy log probs as "old" (they're computed at the same time). More accurate would be to cache log probs during vLLM generation, but vLLM doesn't expose these easily.

---

## Configuration Files

### `configs/baseline.yaml`

```yaml
variant: "baseline"

model:
  model_name: "Qwen/Qwen2.5-0.5B-Instruct"
  lora_enabled: true
  lora_r: 16
  generation_device: "cuda:0"
  training_device: "cuda:1"

generation:
  max_completion_length: 512
  temperature: 0.7
  vllm_gpu_memory_utilization: 0.9

grpo:
  clip_epsilon: 0.2
  kl_beta: 0.04
  group_size: 8  # completions per prompt

training:
  learning_rate: 5e-6
  batch_size: 4
  gradient_accumulation_steps: 4
  max_steps: 1000
  weight_sync_steps: 10
```

### `configs/storpo.yaml`

```yaml
variant: "storpo"

model:
  model_name: "Qwen/Qwen2.5-0.5B-Instruct"
  lora_enabled: true
  lora_r: 16
  generation_device: "cuda:0"
  training_device: "cuda:1"

generation:
  max_completion_length: 512
  temperature: 0.7
  vllm_gpu_memory_utilization: 0.9

grpo:
  clip_epsilon: 0.2
  kl_beta: 0.04

storpo:
  delimiters: [". ", ".\n"]
  completions_per_step: 2
  min_steps: 2
  max_steps: 10

training:
  learning_rate: 5e-6
  batch_size: 4
  gradient_accumulation_steps: 4
  max_steps: 1000
  weight_sync_steps: 10
```

---

## Local Testing Strategy (M1 Mac, 8GB RAM)

Since you can't run full RL locally, we'll add testing modes to verify everything works before cloud deployment.

### 1. Mock Generator Mode

Replace vLLM with a mock that returns canned/random completions:

```python
class MockGenerator:
    """For local testing without vLLM/GPU."""

    def generate(self, prompts, sampling_params, num_completions):
        # Return plausible fake completions for testing data flow
        return [[f"Step 1: Calculate. Step 2: Add. #### 42" for _ in range(num_completions)]
                for _ in prompts]
```

### 2. Tiny Model Mode

Use a tiny transformer config (not real weights) for testing training loop:

```python
# In config.yaml
model:
  model_name: "mock"  # Special value triggers tiny model
  # Creates 1M param model for testing
```

### 3. Dry Run Mode

`--dry-run` flag that:
- Loads config and validates
- Prints what would be generated/trained
- Tests data loading and reward computation
- Skips actual model loading

### 4. Component Tests (run locally)

```bash
# Test STORPO splitting logic
python -m pytest tests/test_storpo.py -v

# Test reward extraction
python -m pytest tests/test_rewards.py -v

# Test rollout buffer advantage computation
python -m pytest tests/test_rollout_buffer.py -v

# Test config loading
python -m pytest tests/test_config.py -v

# Full dry run (no GPU needed)
python scripts/train.py --config configs/storpo.yaml --dry-run
```

### 5. Local Workflow

```bash
# 1. Run all unit tests
python -m pytest tests/ -v

# 2. Dry run to validate config and data flow
python scripts/train.py --config configs/storpo.yaml --dry-run

# 3. Mock run (fake generation, tiny model) - tests full pipeline
python scripts/train.py --config configs/storpo.yaml --mock --max-steps 5

# 4. Deploy to cloud for real training
```

---

## Verification Plan (Cloud)

1. **Training smoke test**: Run 10 steps on small subset, verify loss decreases
2. **Full run**: Train baseline and storpo variants, compare:
   - Training curves (loss, KL, clip fraction)
   - GSM8K accuracy (eval on test set every N steps)
   - Sample completions quality

**Commands:**
```bash
# Install dependencies (uncomment vllm in requirements.txt first)
pip install -r requirements.txt

# Run baseline GRPO
python scripts/train.py --config configs/baseline.yaml

# Run STORPO
python scripts/train.py --config configs/storpo.yaml
```

---

## Files to Create (in order)

**Core:**
1. `requirements.txt`
2. `src/__init__.py` and subpackage `__init__.py` files
3. `src/config.py`
4. `src/data/gsm8k_loader.py`
5. `src/rewards/gsm8k_reward.py`
6. `src/generation/rollout_buffer.py`
7. `src/generation/mock_generator.py` - For local testing
8. `src/generation/vllm_generator.py`
9. `src/variants/base.py` - Abstract base class
10. `src/variants/baseline.py` - Standard GRPO
11. `src/variants/storpo.py` - Step-based variant
12. `src/variants/__init__.py` - Variant registry
13. `src/training/grpo_loss.py`
14. `src/training/trainer.py`
15. `configs/baseline.yaml`
16. `configs/storpo.yaml`
17. `scripts/train.py`

**Tests (for local validation):**
18. `tests/__init__.py`
19. `tests/test_storpo.py`
20. `tests/test_rewards.py`
21. `tests/test_rollout_buffer.py`
22. `tests/test_config.py`
