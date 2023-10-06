{
  description = "This flake patchelfs the wrapped-package's binaries to reference the glibc of the specified nixpkgs instance";

  outputs = { self }:
    let
      libcPatcher =
        # nixpkgs instance from whose stdenv we get libc
        stdenv-nixpkgs:

        # name of the nix package that is derived
        name:

        # the package being patched
        wrapped-package:

        stdenv-nixpkgs.runCommand name {}
        ''
           # bash commands
            # Whitelist of library files from ls -al /path/to/libc/lib, as of glibc-2.35:
            # - We omit files ending in .so (as opposed to .so.<number>). These don't have elf headers.
            # - We omit files ending in .o or .a
            # - omit libc_malloc_debug.so.0, because debug.
            # - omit libthread_db.so.1, because "undefined symble ps_pdwrite" error that requires calling
            #   program to have the symbol. Not sure about this one.
            #
            # caveat: need to audit these files below to ensure they're all appropriate, and not for debug purposes.
            libc_so_libs=(
                ld-linux-x86-64.so.2
                libBrokenLocale.so.1
                libanl.so.1
                libc.so.6
                libdl.so.2
                libgcc_s.so.1
                libm.so.6
                libmvec.so.1
                libnsl.so.1
                libnss_compat.so.2
                libnss_db.so.2
                libnss_dns.so.2
                libnss_files.so.2
                libnss_hesiod.so.2
                libpcprofile.so
                libpthread.so.0
                libresolv.so.2
                librt.so.1
                libutil.so.1
            )
            mkdir $out
            cp -r ${wrapped-package.out}/* $out/
            elf_files=()
            for file in $out/bin/*; do
                    # test if the file is an ELF file
                    interpreter=$(patchelf --print-interpreter $file 2>&1 || true)
                    # the first condition is for patchelf version 0.14.x, and the second condition for patchelf version 0.15.x
                    echo "interpreter output: $interpreter"
                    if [[ $interpreter != "patchelf: missing ELF header" && $interpreter != "patchelf: not an ELF executable" ]]; then
                            elf_files+=($file)
                    fi
            done
            for file in "''${elf_files[@]}"; do
                    echo "patching elf-file $file"
                    # $out/bin/* permissions are r-x, but we need to write to the files, so temporarily allow writes.
                    # We'll undo the write permission at the end of this script, but this is not great b/c an error
                    # in one of the commands below leaves the write permission in place.
                    chmod -R 777 $file
                    patchelf  --set-rpath ${stdenv-nixpkgs.stdenv.cc.libc_lib.outPath}/lib:$(patchelf --print-rpath $file) --interpreter ${stdenv-nixpkgs.stdenv.cc.libc_lib.outPath}/lib/ld-linux-x86-64.so.2 $file
                    for libc_so_lib in "''${libc_so_libs[@]}"; do
                            patchelf --add-needed $libc_so_lib $file
                    done
                    # Neaten the runpath by removing extraneous paths. This will likely remove any old glibc.
                    patchelf --shrink-rpath $file
                    # Undo the write permission, and set the permission back to r-x
                    chmod -R 555 $file
            done
        '';
     in {
        libcPatcher = libcPatcher;
     };
}
