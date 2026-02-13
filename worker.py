"""
Vast.ai PyWorker config for official vastai/acestep image.
Forwards routes to ACE-Step 1.5 API on internal port 8001.
"""

from vastai import Worker, WorkerConfig, HandlerConfig, LogActionConfig, BenchmarkConfig


def benchmark_payload() -> dict:
    """Lightweight generation for benchmarking worker capacity."""
    return {
        "prompt": "A short instrumental test melody",
        "audio_duration": 10.0,
        "inference_steps": 20,
        "guidance_scale": 3.0,
        "use_random_seed": True,
        "audio_format": "mp3",
    }


worker_config = WorkerConfig(
    model_server_url="http://127.0.0.1",
    model_server_port=8001,
    model_log_file="/var/log/ace-step-api.log",
    handlers=[
        HandlerConfig(
            route="/release_task",
            allow_parallel_requests=False,
            max_queue_time=300.0,
            workload_calculator=lambda payload: (
                float(payload.get("audio_duration", 30))
                * float(payload.get("inference_steps", 60))
                / 60.0
            ),
            benchmark_config=BenchmarkConfig(
                generator=benchmark_payload,
                runs=2,
                concurrency=1,
            ),
        ),
        HandlerConfig(
            route="/query_result",
            allow_parallel_requests=True,
            max_queue_time=10.0,
            workload_calculator=lambda _: 0.1,
        ),
        HandlerConfig(
            route="/v1/audio",
            allow_parallel_requests=True,
            max_queue_time=30.0,
            workload_calculator=lambda _: 0.1,
        ),
        HandlerConfig(
            route="/v1/models",
            allow_parallel_requests=True,
            max_queue_time=10.0,
            workload_calculator=lambda _: 0.1,
        ),
        HandlerConfig(
            route="/v1/stats",
            allow_parallel_requests=True,
            max_queue_time=10.0,
            workload_calculator=lambda _: 0.1,
        ),
        HandlerConfig(
            route="/format_input",
            allow_parallel_requests=True,
            max_queue_time=30.0,
            workload_calculator=lambda _: 0.5,
        ),
        HandlerConfig(
            route="/health",
            allow_parallel_requests=True,
            max_queue_time=10.0,
            workload_calculator=lambda _: 0.1,
        ),
    ],
    log_action_config=LogActionConfig(
        on_load=["Application startup complete", "Uvicorn running on"],
        on_error=[
            "RuntimeError:",
            "Traceback (most recent call last):",
            "CUDA out of memory",
            "torch.cuda.OutOfMemoryError",
        ],
        on_info=[
            "Starting ACE-Step",
            "Model loaded",
        ],
    ),
)


if __name__ == "__main__":
    Worker(worker_config).run()
