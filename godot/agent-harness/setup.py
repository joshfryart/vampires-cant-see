from setuptools import setup, find_namespace_packages

setup(
    name="cli-anything-godot",
    version="1.0.0",
    description="Agent-friendly CLI for the Godot Engine (CLI-Anything harness)",
    packages=find_namespace_packages(include=["cli_anything.*"]),
    package_data={"cli_anything.godot": ["skills/*.md"]},
    install_requires=[
        "click>=8.0.0",
        "prompt-toolkit>=3.0.0",
    ],
    entry_points={
        "console_scripts": [
            "cli-anything-godot=cli_anything.godot.godot_cli:main",
        ],
    },
    python_requires=">=3.10",
)
