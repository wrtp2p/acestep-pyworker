"""
Vast.ai PyWorker configuration for ACE-Step 1.5 GPU worker.
Sits alongside the model server as an HTTP proxy, reporting
metrics to the Vast.ai serverless engine for autoscaling.
"""

from vastai import Worker, WorkerConfig, HandlerConfig, LogActionConfig, BenchmarkConfig


def generate_benchmark_payload() -> dict:
    """Generate a lightweight benchmark request for capacity estimation."""
    return {
        "prompt": "A short instrumental test melody",
        "lyrics": "",
        "duration": 10.0,
        "steps": 20,
        "guidance_scale": 3.0,
        "seed": 42,
    }


worker_config = WorkerConfig(
    model_server_url="http://127.0.0.1",
    model_server_port=8000,
    model_log_file="/var/log/acestep/server.log",
    handlers=[
        HandlerConfig(
            route="/generate",
            allow_parallel_requests=False,
            max_queue_time=180.0,
            workload_calculator=lambda payload: float(payload.get("duration", 30)) * float(payload.get("steps", 60)) / 60.0,
            benchmark_config=BenchmarkConfig(
                generator=generate_benchmark_payload,
                runs=2,
                concurrency=1,
            ),
        ),
        HandlerConfig(
            route="/health",
            allow_parallel_requests=True,
            max_queue_time=10.0,
            workload_calculator=lambda _: 0.1,
        ),
    ],
    log_action_config=LogActionConfig(
        on_load=["Application startup complete"],
        on_error=[
            "RuntimeError:",
            "Traceback (most recent call last):",
            "CUDA out of memory",
            "torch.cuda.OutOfMemoryError",
        ],
        on_info=[
            "Starting ACE-Step model server",
            "Initializing service",
        ],
    ),
)


if __name__ == "__main__":
    Worker(worker_config).run()
