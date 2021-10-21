FROM ubuntu:20.10

ENV DEBIAN_FRONTEND noninteractive

# Get the basic stuff
RUN apt-get update && \
    apt-get -y upgrade && \
    apt-get install -y \
    sudo

# Create ubuntu user with sudo privileges
RUN useradd -ms /bin/bash ubuntu && \
    usermod -aG sudo ubuntu
# New added for disable sudo password
RUN echo '%sudo ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers

# Set as default user
USER ubuntu
WORKDIR /home/ubuntu

# Install opam
RUN sudo apt install -y rsync git m4 build-essential patch unzip wget pkg-config libgmp-dev libev-dev libhidapi-dev libffi-dev opam jq zlib1g-dev curl autoconf bc
RUN curl -sL https://raw.githubusercontent.com/ocaml/opam/master/shell/install.sh > /tmp/install.sh
RUN ["/bin/bash", "-c", "sudo /bin/bash /tmp/install.sh --version 2.1.0 <<< /usr/local/bin"]
RUN opam init -y --disable-sandboxing --bare
RUN echo "test -r /home/ubuntu/.opam/opam-init/init.sh && . /home/ubuntu/.opam/opam-init/init.sh > /dev/null 2> /dev/null || true" >> /home/ubuntu/.profile

# Install Rust
RUN wget https://sh.rustup.rs/rustup-init.sh
RUN chmod +x rustup-init.sh
RUN ./rustup-init.sh --profile minimal --default-toolchain 1.52.1 -y
ENV PATH="/home/ubuntu/.cargo/bin:${PATH}"

# Configure opam depext to false
RUN opam option depext=false

# Install Tezos
COPY . /source
WORKDIR /source
RUN find . -type d -exec sudo chmod 777 {} \;
RUN make build-deps
RUN opam exec -- make

# Run tezos unit tests (Enable these when running locally, TODO: investigate why?)
# RUN mkdir -p test_results
# USER root
# RUN chown -R ubuntu:ubuntu test_results
# USER ubuntu
# RUN chmod 777 test_results/*
# RUN chmod 777 test_results
RUN opam exec -- make test-unit
