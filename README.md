# BS ![BS](media/bull.png)

Stay tuned... This may become something awesome, time permitting.

## What is this?

The plan is to make a scripting language with a tiny, ultra-portable runtime. The idea is that you should be able to ship the runtime along with your scripts (e.g. in a Git repo or a tar/zip archive) thus enabling you to run the scripts on just about any machine (Windows, Linux, macOS, BSD, x86, ARM, ...), without having to install any extra software nor even knowing what system you are running on.

## BS Virtual Machine teaser

To run a test program in the [BS Virtual Machine](spec/bsvm.md):

```sh
python3 build.py
out/bs
```
