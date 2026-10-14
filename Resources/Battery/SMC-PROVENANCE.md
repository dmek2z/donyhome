The binary is no longer stored in this repository. `scripts/build-app.sh` compiles `smc-source/` (taken from the upstream project below) into the app bundle. The upstream project is [hholtmann/smcFanControl]( https://github.com/hholtmann/smcFanControl ) by running:

```shell
git clone --depth 1 https://github.com/hholtmann/smcFanControl.git
cd smcFanControl
make
```

Running the above command requires xcode to be installed, either fully of trough `xcode-select`.

The original license of that repository is included here as `./LICENSE`.
