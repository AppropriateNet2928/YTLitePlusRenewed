#!/usr/bin/env python3

import os
import sys
import subprocess
from pathlib import Path


class YTScriptCompiler:

    def __init__(self):

        self.base_dir = Path(__file__).resolve().parent

        self.generator = self.base_dir / "YTScriptGenerator.py"

        if not self.generator.exists():
            print("[YTScript] ERROR: Cannot find YTScriptGenerator.py")
            sys.exit(1)

    def find_xm_files(self):

        files = []

        for file in sorted(os.listdir(".")):

            if (
                file.endswith(".xm")
                and not file.endswith(".processed.xm")
            ):
                files.append(file)

        return files

    def compile_file(self, source):

        output = source.replace(
            ".xm",
            ".processed.xm"
        )

        print(f"[YTScript] Processing {source}")

        command = [

            sys.executable,

            str(self.generator),

            source,

            output

        ]

        result = subprocess.run(command)

        if result.returncode != 0:

            print(f"[YTScript] ERROR while processing {source}")

            sys.exit(result.returncode)

        print(f"[YTScript] Generated {output}")

    def compile_all(self):

        files = self.find_xm_files()

        if not files:

            print("[YTScript] No .xm files found.")

            return

        print(f"[YTScript] Found {len(files)} file(s).")

        for file in files:

            self.compile_file(file)

        print("[YTScript] Done.")


def main():

    compiler = YTScriptCompiler()

    compiler.compile_all()


if __name__ == "__main__":

    main()
