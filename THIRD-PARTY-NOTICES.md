# Third-Party Notices

AlfredMeetings (the source in this repository) is licensed under the [MIT License](LICENSE).

It relies on third-party software at **install and run time**, but **does not bundle or
redistribute any of it**. `setup/install.sh` fetches these components onto your machine:
the Python packages via `pip` (into `~/Library/Application Support/AlfredMeetings/venv`)
and the command-line tools via Homebrew. Each component remains under its own license,
listed below for reference and convenience.

Because nothing here is redistributed, these licenses impose no obligations on this
project's source. In particular, **ffmpeg** is the copyleft (GPL) Homebrew build but is
only invoked as a separate process, so its terms do not extend to this code.

## Command-line tools (Homebrew)

| Tool | License | Project |
|---|---|---|
| `ffmpeg` | GPL-3.0 (Homebrew `--enable-gpl --enable-version3` build) | <https://ffmpeg.org/> |
| `ollama` | MIT | <https://github.com/ollama/ollama> |
| `switchaudio-osx` (`SwitchAudioSource`) | MIT | <https://github.com/deweller/switchaudio-osx> |

`ollama` additionally serves a local language model (default `qwen3:4b-instruct`); models
are downloaded separately and carry their own model-use licenses.

## Apple frameworks

The native helpers (`MeetingCapture.swift`, `RecIndicator.swift`) link only Apple system
frameworks (CoreAudio, AudioToolbox, AppKit/Cocoa, Foundation). These ship with macOS
under the Apple SDK license and carry no third-party redistribution obligation.

## Python packages

Directly requested by `setup/install.sh`:

| Package | License | Project |
|---|---|---|
| `mlx-whisper` | MIT | <https://github.com/ml-explore/mlx-examples> |
| `openai` | Apache-2.0 | <https://github.com/openai/openai-python> |
| `pyannote.audio` | MIT | <https://github.com/pyannote/pyannote-audio> |

### Full installed dependency tree

The complete venv (110 packages, including transitive dependencies) and the license of
each. Licenses are given as SPDX identifiers where available; `see project` marks the
pyannote suite, whose distributions ship no license metadata but are published under the
MIT License (see each project's `LICENSE`).

| Package | Version | License |
|---|---|---|
| `aiohappyeyeballs` | 2.6.2 | PSF-2.0 |
| `aiohttp` | 3.14.1 | Apache-2.0 AND MIT |
| `aiosignal` | 1.4.0 | Apache-2.0 |
| `alembic` | 1.18.4 | MIT |
| `annotated-doc` | 0.0.4 | MIT |
| `annotated-types` | 0.7.0 | MIT |
| `anyio` | 4.14.0 | MIT |
| `asteroid-filterbanks` | 0.4.0 | MIT |
| `attrs` | 26.1.0 | MIT |
| `certifi` | 2026.6.17 | MPL-2.0 |
| `charset-normalizer` | 3.4.7 | MIT |
| `click` | 8.4.1 | BSD-3-Clause |
| `colorlog` | 6.10.1 | MIT |
| `contourpy` | 1.3.3 | BSD-3-Clause |
| `cycler` | 0.12.1 | BSD-3-Clause |
| `distro` | 1.9.0 | Apache-2.0 |
| `einops` | 0.8.2 | MIT |
| `filelock` | 3.29.4 | MIT |
| `fonttools` | 4.63.0 | MIT |
| `frozenlist` | 1.8.0 | Apache-2.0 |
| `fsspec` | 2026.6.0 | BSD-3-Clause |
| `googleapis-common-protos` | 1.75.0 | Apache-2.0 |
| `grpcio` | 1.81.1 | Apache-2.0 |
| `h11` | 0.16.0 | MIT |
| `hf-xet` | 1.5.1 | Apache-2.0 |
| `httpcore` | 1.0.9 | BSD-3-Clause |
| `httpx` | 0.28.1 | BSD-3-Clause |
| `huggingface_hub` | 1.20.0 | Apache-2.0 |
| `idna` | 3.18 | BSD-3-Clause |
| `Jinja2` | 3.1.6 | BSD-3-Clause |
| `jiter` | 0.15.0 | MIT |
| `joblib` | 1.5.3 | BSD-3-Clause |
| `julius` | 0.2.8 | MIT |
| `kiwisolver` | 1.5.0 | BSD-3-Clause |
| `lightning` | 2.6.5 | Apache-2.0 |
| `lightning-utilities` | 0.15.3 | Apache-2.0 |
| `llvmlite` | 0.47.0 | BSD-2-Clause AND Apache-2.0 WITH LLVM-exception |
| `Mako` | 1.3.12 | MIT |
| `markdown-it-py` | 4.2.0 | MIT |
| `MarkupSafe` | 3.0.3 | BSD-3-Clause |
| `matplotlib` | 3.11.0 | PSF-2.0 |
| `mdurl` | 0.1.2 | MIT |
| `mlx` | 0.31.2 | MIT |
| `mlx-metal` | 0.31.2 | MIT |
| `mlx-whisper` | 0.4.3 | MIT |
| `more-itertools` | 11.1.0 | MIT |
| `mpmath` | 1.3.0 | BSD-3-Clause |
| `multidict` | 6.7.1 | Apache-2.0 |
| `narwhals` | 2.22.1 | MIT |
| `networkx` | 3.6.1 | BSD-3-Clause |
| `numba` | 0.65.1 | BSD-3-Clause |
| `numpy` | 2.4.6 | BSD-3-Clause AND 0BSD AND MIT AND Zlib AND CC0-1.0 |
| `openai` | 2.43.0 | Apache-2.0 |
| `opentelemetry-api` | 1.42.1 | Apache-2.0 |
| `opentelemetry-exporter-otlp` | 1.42.1 | Apache-2.0 |
| `opentelemetry-exporter-otlp-proto-common` | 1.42.1 | Apache-2.0 |
| `opentelemetry-exporter-otlp-proto-grpc` | 1.42.1 | Apache-2.0 |
| `opentelemetry-exporter-otlp-proto-http` | 1.42.1 | Apache-2.0 |
| `opentelemetry-proto` | 1.42.1 | Apache-2.0 |
| `opentelemetry-sdk` | 1.42.1 | Apache-2.0 |
| `opentelemetry-semantic-conventions` | 0.63b1 | Apache-2.0 |
| `optuna` | 4.9.0 | MIT |
| `packaging` | 26.2 | Apache-2.0 OR BSD-2-Clause |
| `pandas` | 3.0.3 | BSD-3-Clause |
| `pillow` | 12.2.0 | MIT-CMU |
| `pip` | 26.1.2 | MIT |
| `primePy` | 1.3 | MIT |
| `propcache` | 0.5.2 | Apache-2.0 |
| `protobuf` | 6.33.6 | BSD-3-Clause |
| `pyannote-audio` | 4.0.4 | MIT (see project) |
| `pyannote-core` | 6.0.1 | MIT (see project) |
| `pyannote-database` | 6.1.1 | MIT (see project) |
| `pyannote-metrics` | 4.1 | MIT (see project) |
| `pyannote-pipeline` | 4.0.0 | MIT (see project) |
| `pyannoteai-sdk` | 0.4.0 | MIT |
| `pydantic` | 2.13.4 | MIT |
| `pydantic_core` | 2.46.4 | MIT |
| `Pygments` | 2.20.0 | BSD-2-Clause |
| `pyparsing` | 3.3.2 | MIT |
| `python-dateutil` | 2.9.0.post0 | BSD-3-Clause; Apache-2.0 |
| `pytorch-lightning` | 2.6.5 | Apache-2.0 |
| `pytorch-metric-learning` | 2.9.0 | MIT |
| `PyYAML` | 6.0.3 | MIT |
| `regex` | 2026.5.9 | Apache-2.0 AND CNRI-Python |
| `requests` | 2.34.2 | Apache-2.0 |
| `rich` | 15.0.0 | MIT |
| `safetensors` | 0.8.0 | Apache-2.0 |
| `scikit-learn` | 1.9.0 | BSD-3-Clause |
| `scipy` | 1.17.1 | BSD-3-Clause |
| `setuptools` | 81.0.0 | MIT |
| `shellingham` | 1.5.4 | ISC |
| `six` | 1.17.0 | MIT |
| `sniffio` | 1.3.1 | MIT; Apache-2.0 |
| `sortedcontainers` | 2.4.0 | Apache-2.0 |
| `SQLAlchemy` | 2.0.51 | MIT |
| `sympy` | 1.14.0 | BSD-3-Clause |
| `threadpoolctl` | 3.6.0 | BSD-3-Clause |
| `tiktoken` | 0.13.0 | MIT |
| `torch` | 2.12.1 | BSD-3-Clause |
| `torch-audiomentations` | 0.12.0 | MIT |
| `torch_pitch_shift` | 1.2.5 | MIT |
| `torchaudio` | 2.11.0 | BSD-3-Clause |
| `torchcodec` | 0.14.0 | BSD-3-Clause |
| `torchmetrics` | 1.9.0 | Apache-2.0 |
| `tqdm` | 4.68.3 | MPL-2.0 AND MIT |
| `typer` | 0.25.1 | MIT |
| `typing-inspection` | 0.4.2 | MIT |
| `typing_extensions` | 4.15.0 | PSF-2.0 |
| `urllib3` | 2.7.0 | MIT |
| `yarl` | 1.24.2 | Apache-2.0 |

_Versions reflect the resolved environment at the time of writing; `pip` may resolve
newer compatible versions on a fresh install._
