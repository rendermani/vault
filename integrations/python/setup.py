#!/usr/bin/env python3
"""
Setup script for Vault Infrastructure Integration SDK
"""

from setuptools import setup, find_packages
import os

# Read README for long description
def read_readme():
    try:
        with open('README.md', 'r', encoding='utf-8') as f:
            return f.read()
    except FileNotFoundError:
        return "Vault Infrastructure Integration SDK for Python"

# Read requirements
def read_requirements():
    with open('requirements.txt', 'r') as f:
        return [line.strip() for line in f if line.strip() and not line.startswith('#')]

setup(
    name="vault-infrastructure-sdk",
    version="1.0.0",
    author="Vault Integration Team",
    author_email="devops@company.com",
    description="Python SDK for integrating with Vault infrastructure services",
    long_description=read_readme(),
    long_description_content_type="text/markdown",
    url="https://github.com/company/vault-infrastructure-sdk",
    packages=find_packages(),
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Intended Audience :: Developers",
        "License :: OSI Approved :: MIT License",
        "Operating System :: OS Independent",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: System :: Systems Administration",
        "Topic :: Internet :: WWW/HTTP :: Dynamic Content",
    ],
    python_requires=">=3.8",
    install_requires=read_requirements(),
    extras_require={
        'dev': [
            'pytest>=7.0.0',
            'pytest-asyncio>=0.21.0',
            'pytest-mock>=3.10.0',
            'black>=23.0.0',
            'flake8>=6.0.0',
            'mypy>=1.0.0',
        ],
        'monitoring': [
            'opentelemetry-api>=1.20.0',
            'opentelemetry-sdk>=1.20.0',
            'opentelemetry-instrumentation>=0.41b0',
        ]
    },
    entry_points={
        'console_scripts': [
            'vault-sdk-cli=vault_integration_sdk.cli:main',
        ],
    },
    include_package_data=True,
    zip_safe=False,
)