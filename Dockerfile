###############################################################################
# Build this stage for a build environment, e.g.:                             #
#                                                                             #
# docker build --tag mpspdz:buildenv --target buildenv .                      #
#                                                                             #
# The above is equivalent to:                                                 #
#                                                                             #
#   docker build --tag mpspdz:buildenv \                                      #
#     --target buildenv \                                                     #
#     --build-arg arch=native \                                               #
#     --build-arg cxx=clang++-11 \                                            #
#     --build-arg use_ntl=0 \                                                 #
#     --build-arg prep_dir="Player-Data" \                                    #
#     --build-arg ssl_dir="Player-Data"                                       #
#     --build-arg cryptoplayers=0                                             #
#                                                                             #
# To build for an x86-64 architecture, with g++, NTL (for HE), custom         #
# prep_dir & ssl_dir, and to use encrypted channels for 4 players:            #
#                                                                             #
#   docker build --tag mpspdz:buildenv \                                      #
#     --target buildenv \                                                     #
#     --build-arg arch=x86-64 \                                               #
#     --build-arg cxx=g++ \                                                   #
#     --build-arg use_ntl=1 \                                                 #
#     --build-arg prep_dir="/opt/prepdata" \                                  #
#     --build-arg ssl_dir="/opt/ssl"                                          #
#     --build-arg cryptoplayers=4 .                                           #
#                                                                             #
# To work in a container to build different machines, and compile programs:   #
#                                                                             #
# docker run --rm -it mpspdz:buildenv bash                                    #
#                                                                             #
# Once in the container, build a machine and compile a program:               #
#                                                                             #
#   $ make replicated-ring-party.x                                            #
#   $ ./compile.py -R 64 tutorial                                             #
#                                                                             #
###############################################################################
FROM python:3.10.3-bullseye as buildenv

RUN apt-get update && apt-get install -y --no-install-recommends \
                automake \
                build-essential \
                clang-11 \
		cmake \
                git \
                libboost-dev \
                libboost-thread-dev \
                libclang-dev \
                libgmp-dev \
                libntl-dev \
                libsodium-dev \
                libssl-dev \
                libtool \
                vim \
                gdb \
                valgrind \
        && rm -rf /var/lib/apt/lists/*

ENV MP_SPDZ_HOME /usr/src/MP-SPDZ
WORKDIR $MP_SPDZ_HOME

RUN pip install --upgrade pip ipython

# Copy top-level files
COPY Makefile .
COPY compile.py .
COPY CONFIG .
COPY setup.py .
COPY License.txt .
COPY README.md .
COPY CHANGELOG.md .
COPY .gitignore .
COPY .gitmodules .
COPY .readthedocs.yaml .
COPY azure-pipelines.yml .

# Copy folders
COPY .github/ .github/
COPY bin/ bin/
COPY BMR/ BMR/
COPY Compiler/ Compiler/
COPY deps/ deps/
COPY doc/ doc/
COPY ECDSA/ ECDSA/
COPY ExternalIO/ ExternalIO/
COPY FHE/ FHE/
COPY FHEOffline/ FHEOffline/
COPY GC/ GC/
COPY Machines/ Machines/
COPY Math/ Math/
COPY Networking/ Networking/
COPY OT/ OT/
COPY Processor/ Processor/
# COPY Programs/ Programs/
COPY Protocols/ Protocols/
COPY Scripts/ Scripts/
COPY Tools/ Tools/
COPY Utils/ Utils/
COPY Yao/ Yao/


ARG arch=
ARG cxx=clang++-11
ARG use_ntl=0
ARG prep_dir="Player-Data"
ARG ssl_dir="Player-Data"

RUN if test -n "${arch}"; then echo "ARCH = -march=${arch}" >> CONFIG.mine; fi
RUN echo "CXX = ${cxx}" >> CONFIG.mine \
        && echo "USE_NTL = ${use_ntl}" >> CONFIG.mine \
        && echo "MY_CFLAGS += -I/usr/local/include" >> CONFIG.mine \
        && echo "MY_LDLIBS += -Wl,-rpath -Wl,/usr/local/lib -L/usr/local/lib" \
            >> CONFIG.mine \
        && mkdir -p $prep_dir $ssl_dir \
        && echo "PREP_DIR = '-DPREP_DIR=\"${prep_dir}/\"'" >> CONFIG.mine \
        && echo "SSL_DIR = '-DSSL_DIR=\"${ssl_dir}/\"'" >> CONFIG.mine

# ssl keys
ARG cryptoplayers=
ENV PLAYERS ${cryptoplayers}
RUN ./Scripts/setup-ssl.sh "${cryptoplayers}" ${ssl_dir}

RUN make clean-deps boost libote

###############################################################################
# Use this stage to a build a specific virtual machine. For example:          #
#                                                                             #
#   docker build --tag mpspdz:shamir \                                        #
#     --target machine \                                                      #
#     --build-arg machine=shamir-party.x \                                    #
#     --build-arg gfp_mod_sz=4 .                                              #
#                                                                             #
# The above will build shamir-party.x with 256 bit length.                    #
#                                                                             #
# If no build arguments are passed (via --build-arg), mascot-party.x is built #
# with the default 128 bit length.                                            #
###############################################################################
FROM buildenv as machine

ARG machine="mascot-party.x"

ARG gfp_mod_sz=2

RUN echo "MOD = -DGFP_MOD_SZ=${gfp_mod_sz}" >> CONFIG.mine

RUN make clean && make ${machine} && cp ${machine} /usr/local/bin/
RUN echo MY_CFLAGS += -DINSECURE >> CONFIG.mine
RUN make Fake-Offline.x && cp Fake-Offline.x /usr/local/bin/

################################################################################
# This is the default stage. Use it to compile a high-level program.           #
# By default, tutorial.mpc is compiled with --field=64 bits.                   #
#                                                                              #
#   docker build --tag mpspdz:mascot-tutorial \                                #
#     --build-arg src=tutorial \                                               #
#     --build-arg compile_options="--field=64" .                               #
#                                                                              #
# Note that build arguments from previous stages can also be passed. For       #
# instance, building replicated-ring-party.x, for 3 crypto players with custom #
# PREP_DIR and SSL_DIR, and compiling tutorial.mpc with --ring=64:             #
#                                                                              #
#   docker build --tag mpspdz:replicated-ring \                                #
#           --build-arg machine=replicated-ring-party.x \                      #
#           --build-arg prep_dir=/opt/prep \                                   #
#           --build-arg ssl_dir=/opt/ssl \                                     #
#           --build-arg cryptoplayers=3 \                                      #
#           --build-arg compile_options="--ring=64" .                          #
#                                                                              #
# Test it:                                                                     #
#                                                                              #
#   docker run --rm -it mpspdz:replicated-ring ./Scripts/ring.sh tutorial      #
################################################################################
FROM machine as program

COPY anon/ ./anon/

ARG src="anonymous_inclusion_iterative"

# 1. Add your NEW MPC script and Python helper scripts
ADD Programs/Source/anonymous_inclusion_iterative.mpc Programs/Source/
COPY anon/*.py ./

RUN chmod +x ./generate_mempool.py \
             ./generate_inputs.py \
             ./prepare_iteration_inputs.py \
             ./run_iterative_workflow.py \
             ./parse_log.py

# 2. Setup Configuration parameters
ARG NUM_PARTIES_ARG=16
ARG TRANSACTION_SPACE_BITS_ARG=40
ARG BRANCH_FACTOR_LOG2_ARG=2
ARG MIN_VOTES_THRESHOLD_ARG=10
ARG MEMPOOL_SIZE_ARG=100
ARG VOTES_PER_PARTY_ARG=100

# loaded for compiling the MPC script
ENV NUM_PARTIES=${NUM_PARTIES_ARG} 
ENV TRANSACTION_SPACE_BITS=${TRANSACTION_SPACE_BITS_ARG}
# loaded for compiling the MPC script
ENV BRANCH_FACTOR_LOG2=${BRANCH_FACTOR_LOG2_ARG} 
ENV MIN_VOTES_THRESHOLD=${MIN_VOTES_THRESHOLD_ARG}
# loaded for compiling the MPC script
ENV MEMPOOL_SIZE=${MEMPOOL_SIZE_ARG} 
ENV VOTES_PER_PARTY=${VOTES_PER_PARTY_ARG}
ENV MAX_PREFIX_SLOTS=${MEMPOOL_SIZE_ARG}
ENV PLAYERS=${NUM_PARTIES}

RUN Scripts/setup-online.sh ${NUM_PARTIES}

# 3. Compile the MPC script (once)
# The .mpc script now reads all its config from ENV variables.
# NUM_PARTIES is also read from ENV by the .mpc script's compile-time Python.

RUN ./compile.py anonymous_inclusion_iterative.mpc ${NUM_PARTIES}

# 4. Setup SSL (if needed for the protocol, e.g., some *-party.x require it)
# RUN Scripts/setup-ssl.sh ${NUM_PARTIES}

# 5. Execute the entire iterative workflow using the Python orchestrator
RUN python3 ./run_iterative_workflow.py mascot

# --- End of setup for Iterative Anonymous Inclusion ---

CMD ["bash"]