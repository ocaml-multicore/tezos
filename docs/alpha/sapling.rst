**The features described in this page are experimental and have not  undergone any security review.**

Sapling integration
===================

Sapling is a protocol enabling privacy-preserving transactions of fungible
tokens in a decentralised
environment. It was designed and implemented by the Electric Coin
Company as the last iteration over a series of previous protocols and
academic works starting with the `Zerocoin seminal
paper <http://zerocoin.org/media/pdf/ZerocoinOakland.pdf>`_.

The reference implementation of Sapling,
`librustzcash <https://github.com/zcash/librustzcash>`_, was
integrated in the Tezos codebase during 2019. It will be proposed as
part of a protocol amendment during 2020.

Librustzcash and the Tezos integration implement the protocol
described in this `specification
<https://github.com/zcash/zips/blob/2e26bb072dfd5f842fe9e779bdec8cabeb4fa9bf/protocol/protocol.pdf>`_, version 2020.1.0.


Sapling
-------

Keys
~~~~

Sapling offers a rich set of keys, each allowing different operations.
A `spending key` allows to spend tokens so if it is lost or
compromised the tokens could remain locked or be stolen.
From a spending key it is possible to derive a corresponding `viewing
key` which allows to view all incoming and outgoing transactions.
The viewing key allows the owner of the tokens to check their balance
and transaction history so if compromised there is a complete loss of
privacy.
On the other hand a viewing key can willingly be shared with a third
party, for example with an auditor for regulatory compliance purposes.

A viewing key can also derive several diversified `addresses`.
An address can be used to receive funds, much like the address of an
implicit account.

Additionally `proving keys` can be used to allow the creation of proofs,
thus revealing private information, without being able to spend funds.
They are useful for example in case the spending key is stored in a
hardware wallet but we'd like to use our laptop to craft the
transaction and produce the zero-knowledge proofs, which are
computationally too intensive for an embedded device.

More details can be found in the `specification document
<https://github.com/zcash/zips/blob/main/protocol/sapling.pdf>`_.

Shielded transactions
~~~~~~~~~~~~~~~~~~~~~

Transactions use Bitcoin's UTXO model with the important difference that each
input and output, instead of containing an amount and an address,
are just cryptographic `commitments`.
In order to avoid double spends, it's important to be able to check
that a commitment has not already been spent. In Bitcoin we just need to
check if an output is also later used as an input to verify if it's
already spent. In Sapling however we can't know because inputs are not
linked to outputs.
For this reason for each input of a transaction, the owner must also
publish a `nullifier`, which invalidates it. The nullifier can only be
produced by the owner of a commitment and it's deterministic so that
everybody can check that it hasn't been already published.
Note however that it is not possible to infer which commitment has
been nullified.
Transactions of this form are privacy preserving and are referred to
as `shielded`, because they reveal neither the amount, the sender nor
the receiver.

The existing set of transactions is referred to as the `shielded pool`.
Unlike Bitcoin, where everybody can compute the set of unspent
outputs of every user, in Sapling only the owner of a viewing key can
find their outputs and verify that they are not already spent.
For this reason, to an external
observer, the shielded pool is always increasing in size and the more
transactions are added the harder it is to pinpoint the commitments
belonging to a user.

When we spend a commitment there is some additional information that
we need to transmit to the recipient in order for them to spend the
corresponding output.
This data is encrypted under a symmetric key resulting from a
Diffie-Hellman key exchange using the recipient address and an
ephemeral key.
In principle this `ciphertext` can be transmitted off-chain as it's
not needed to verify the integrity of the pool. For convenience, in
Tezos, it is stored together with the commitment and the nullifier on
chain.

For reasons of efficiency the commitments are stored in an incremental
`Merkle tree <https://en.wikipedia.org/wiki/Merkle_tree>`_ which
allows for compact proofs of membership. The root of the tree is all
that is needed to refer to a certain state of the shielded pool.

In order to ensure the correctness of a transaction, given that there
is information that we wish to remain secret, the spender must also
generate proofs that various good properties are true.
Thanks to the use of `SNARKs <https://z.cash/technology/zksnarks/>`_
these proofs are very succinct in size, fast to verify and they don't
reveal any private information.

This model of transaction adapts elegantly to the case when we need to
mint or burn tokens, which is needed to shield or unshield from a
transparent token.
It suffices to add more values in the outputs than in the inputs
to mint and to have more in inputs than outputs to burn.

Privacy guarantees
~~~~~~~~~~~~~~~~~~

We explained that the shielded pool contains one commitment for each
input (spent or not), and one nullifier for each spent input.
These cryptographic commitments hide the amount and the owner of the
tokens they represent.
Additionally commitments are unlinkable meaning that we can not deduce
which input is spent to create an output.

It should be noted that the number of inputs and outputs of a
transaction is public, which could help link a class of
transactions. This problem can be mitigated by adding any number of
dummy inputs or outputs at the cost of wasting some space.

The shielded pool communicates with the public ledger by minting and
burning shielded tokens in exchange for public coins.
Therefore going in and out of the shielded pool is public: we know
which address shielded or unshielded and how much.
We can among other things infer the total number of shielded coins.

Timing and network information can also help to deduce some private
information.
For example by observing the gossip network we might learn the IP
address of somebody that is submitting a shielded transaction.
This can be mitigated by using `TOR
<https://en.wikipedia.org/wiki/Tor_(anonymity_network)>`_.

Good practices
~~~~~~~~~~~~~~

When blending in a group of people, one should always pay attention to
the size and the variety of the group.

We recommend two good practices. First, do not originate a second
contract if another one has the same functionalities, it will split
the anonymity set.

Second, remember that shielding and unshielding are public operations.
A typical anti-pattern is to shield from tz1-alice 15.3 tez, and then
unshield 15.3 tez to tz1-bob. It's fairly clear from timing and
amounts that Alice transferred 15.3 tez to Bob.
To decorrelate the two transfers it is important to change the
amounts, let some time pass between the two and perform the
transactions when there is traffic in the pool.
Similar problems exist in Zcash and they are illustrated in this
introductory `blog post
<https://electriccoin.co/blog/transaction-linkability/>`_.

There are a number of more sophisticated techniques to deanonymise
users using timing of operations, network monitoring, side-channels on
clients and analysis of number of inputs/outputs just to mention a few
(`A fistful of Bitcoins
<https://dblp.org/rec/journals/cacm/MeiklejohnPJLMV16.html>`_ is a good
first read).
We advice users to be familiar with the use of the TOR network and to
use clients developed specifically to protect their privacy.


Tezos integration
-----------------

Michelson: verify update
~~~~~~~~~~~~~~~~~~~~~~~~

We introduce two new Michelson types `sapling_state` and
`sapling_transaction`, and two instructions called
`SAPLING_VERIFY_UPDATE` and `SAPLING_EMPTY_STATE`
(see the :doc:`Michelson reference<michelson>`
for more details).
`SAPLING_EMPTY_STATE` pushes an empty `sapling_state` on the stack.
`SAPLING_VERIFY_UPDATE` takes a transaction and a state and returns an
option type which is Some (updated
state and a balance) if the transaction is correct, None otherwise.
A transaction has a list of inputs, outputs, a signature, a balance,
and the root of the Merkle tree containing its inputs.
The verification part checks the zero-knowledge proofs of all inputs
and outputs of the transaction, which guarantee several properties of
correctness.
It also checks a (randomised) signature associated with each input
(which guarantees that the owner forged the transaction), and the
signature that binds the whole transaction together and guarantees the
correctness of the balance.
All the signatures are over the hash of the data that we wish to sign
and the hash function used is Blake2-b, prefixed with the anti-replay string.
The anti-replay string is the the concatenation of the chain id and
the smart contract address. The same string has to be used by the client for
signing.

Verify_update also checks that the root of the Merkle tree appears in
one of the past states and that the nullifiers are not already
present (i.e. no double spending is happening).
If one of the checks fails the instruction returns None.

Otherwise the function adds to the new state the nullifiers given with each inputs
and adds the outputs to the Merkle tree, which will produce a new root.
It should be noted that it is possible to generate transactions
referring to an old root, as long as the inputs used were present in
the Merkle tree with that root and were not spent after.
In particular the protocol keeps 120 previous roots and guarantees
that roots are updated only once per block.
Considering 1 block per minute and that each block contains at least
one call to the same contract, a client has 2 hours to have its
transaction accepted before it is considered invalid.

The nullifiers are stored in a set. The ciphertexts and other relevant
information linked to the commitment of the Merkle tree are
stored in a map indexed by the position of the commitment in the
Merkle tree.

Lastly the instruction pushes the updated state and the balance as an option
on the stack.

Example contracts
~~~~~~~~~~~~~~~~~

Shielded tez
^^^^^^^^^^^^

An example contract to have a shielded tez with a 1 to 1 conversion to
tez is available in the tests of `lib_sapling`.

Simple Vote Contract
^^^^^^^^^^^^^^^^^^^^

One might think to use Sapling to do private voting.
It is possible to adapt shielded transactions to express preferences.
**Note that this is not what Sapling is designed for and it doesn't provide the same properties as an actual private voting protocol.**
A natural naive idea is the following.
Suppose we want a set of users to express a preference for option A or
B, we can generate two Sapling keys with two addresses that are
published and represent the two options.
The contract lets each user create a token which represents one vote
that can then be transferred to address A or B.
Using the published viewing keys everyone can check the outcome of the
vote.
**However note that a transaction can be replayed and we can see the balance of A or B going up.
This system does not offer ballot privacy.
Therefore one should ensure that the vote he is casting cannot be linked to him.
It is possible that the practical situation makes this usable but we recommend in general not to use
it for any important vote.**
Note that using a random elliptic curve element as incoming viewing key allows to generate a
dummy address that cannot be spent. This eases the counting of the votes.
To ensure that the ivk does not correspond to a normal address with spending key, one
can use the Fiat-Shamir heuristic.


Fees issue
~~~~~~~~~~

We have an additional privacy issue that Z-cash doesn't have. When
interacting with a shielded pool we interact with a smart contract
with a normal transaction and therefore have to pay fees from an
implicit account.
One could guess that private transactions whose fees are paid by the
same implicit account are from the same user.
This can be mitigated by making a service that act as a proxy by
forwarding the user transactions and paying it fees. The user would
then include in the transaction a shielded output for the service that
covers the fees plus a small bonus to pay the service.
This output can be open by the service before sending the transaction
to check that there is enough money to cover its fees. As for Z-cash,
users interacting with the proxy should use TOR or mitigate network
analysis as they wish.

Gas, storage and costs
~~~~~~~~~~~~~~~~~~~~~~

Gas evaluation is not yet done.

RPCs
~~~~

There are two Sapling RPCs under the prefix `context/sapling`.
`get_size` returns a pair with the size of the set of commitments
and the size of the set of nullifiers.
`get_diff` takes two optional starting offsets `cm_from` and `nf_from`
and returns the sapling state that was added from the offsets to the
current size. In particular it returns three lists, commitments,
ciphertexts from position `cm_from` up to the last one added and
nullifiers, from `nf_from` to the last one added.
Additionally it returns the last computed root of the merkle tree so
that a client updating its tree using the diff can verify the
correctness of the result.

Client
~~~~~~

Wallet
^^^^^^

tezos-client supports Sapling keys and can send
shielded transactions to smart contracts.

The client supports two ways to generate a new Sapling spending key.
It can be generated from a mnemonic using `BIP39
<https://github.com/bitcoin/bips/blob/master/bip-0039.mediawiki>`_, so
that it can be recovered in case of loss using the mnemonic.
Alternatively it is possible to derive new keys from existing ones
using `ZIP32
<https://github.com/zcash/zips/blob/main/zip-0032.rst>`_, a Sapling
variant of `BIP32
<https://github.com/bitcoin/bips/blob/master/bip-0032.mediawiki>`_ for
hierarchical deterministic wallets. As usual, in this case it is
important to note the derivation path of the key to be able to recover
it in case of loss.
At the moment there is no hardware wallet support, keys are stored in
`~/.tezos-client/sapling_keys` by default encrypted with a password.
**Users should take care to backup this file.**

The client can also derive addresses from viewing keys.
By default addresses are generated using an increasing counter called
the address index. Not all indexes correspond to valid addresses for
each key so it is normal to see an increasing counter that
occasionally skips a few positions.

Because for now the only support for Sapling keys is to interact with
smart contracts, the client binds each newly generated key to a
specific smart contract address.

Operations
^^^^^^^^^^

The client also facilitates the creation of shielded transactions and
their transfer as arguments of smart contracts.
For now there is seamless integration to send transactions to the
reference shielded-tez contract and we are planning to support a
larger class of contracts.

For the shielded-tez smart contract, the client supports shielding,
unshielding and shielded transactions.
In the case of shielded transactions there are two commands, one to
forge a transaction and save it to file and one to submit it to the
smart contract.
The idea is that a user should not use their own transparent tz{1,2,3}
address to submit a shielded address but rather have a third party
inject it.

Message argument
^^^^^^^^^^^^^^^^
Sapling also allows to send an arbitrary encrypted message attached
to an output.
The message size has to be fixed by pool for privacy reasons.
For now it is fixed overall at eight bytes. An incorrect message length
will raise a failure in our client and the protocol will reject the
transaction. Our client adds a default zero's filled message of the
right length. If a message is provided with the --message option,
the client will pad it or truncate it if necessary. A warning message
is printed only if the user's message is truncated.


Code base
~~~~~~~~~

The current code-base is organized in three main components.
There is a core library called `lib_sapling` which binds `librustzcash`,
adds all the data structures necessary to run the sapling
protocol and includes a simple client and baker.
Under the protocol directory there is a `lib_client_sapling` library
which implements a full client capable of handling Sapling keys and
forging transactions.
Lastly in the protocol there is a efficient implementation of the
Sapling storage, in the spirit of `big_map`s, and the integration of
`SAPLING_VERIFY_UPDATE` in the Michelson interpreter.

Protocol
^^^^^^^^

In order to export the Sapling library to the protocol we first need
to expose it through the environment that sandboxes the protocol.
The changes under `src/lib_protocol_environment` are simple but very
relevant as any change of the environment requires a manual update of the
Tezos node. These changes are part of version V1 of the environment
while protocols 000 to 006 depends on version V0.

There are two main changes to Tezos' economic protocol, the storage
for Sapling and the addition of `SAPLING_VERIFY_UPDATE` to the Michelson
interpreter.

Given that the storage of a Sapling contract can be substantially
large, it is important to provide an efficient implementation.
Similarly to what it's done for big_maps, the storage of Sapling can't
be entirely deserialized and modified in memory but only a diff of the
changes is kept by the interpreter and applied at the end of each
smart contract call.

In the Michelson interpreter two new types are added, `sapling_state` and
`sapling_transaction`, and the instruction `SAPLING_VERIFY_UPDATE`.

Client
^^^^^^

Under `lib_client_sapling` there is the client integration
with the support for Sapling keys and forging of transactions.
The main difference from the existing Tezos client is the need for the
Sapling client to keep an additional state, for each contract.
Because Sapling uses a UTXO model it is necessary for a client to
compute the set of unspent outputs in order to forge new transactions.
Computing this set requires scanning all the state of a contract which
can be expensive.
For this reason the client keeps a local state of the unspent outputs
after the last synchronization and updates it before performing any
Sapling command.
The update is done using the RPCs to recover the new updates since the
last known position.

The state of all sapling contracts is stored in
`~/.tezos-client/sapling_states`. This file can be regenerated from
the chain in case of loss. However disclosure of this file will reveal
the balance and the unspent outputs of all viewing keys.

Memo
^^^^^^

Sapling offers the possibility to add an arbitrary memo to any
created output. The memo is encrypted and available to anyone
owning the outgoing viewing key or the spending key.
For privacy reasons the size of the memo is fixed per contract
and it is chosen at origination time.
A transaction containing an output with a different memo-size
will be rejected.

Sandbox tutorial
~~~~~~~~~~~~~~~~

As usual it's possible to test the system end-to-end using the
:doc:`../user/sandbox`.
After having set up the sandbox and originated the contract, a good
way to get familiar with the system is to generate keys and then
perform the full cycle of shielding, shielded transfer and
unshielding.

::

   # set up the sandbox
   ./src/bin_node/tezos-sandboxed-node.sh 1 --connections 0 &
   eval `./src/bin_client/tezos-init-sandboxed-client.sh 1`
   tezos-activate-alpha

   # originate the contract with its initial empty sapling storage,
   # bake a block to include it.
   # { } represents an empty Sapling state.
   tezos-client originate contract shielded-tez transferring 0 from bootstrap1 \
   running src/proto_alpha/lib_protocol/test/integration/michelson/contracts/sapling_contract.tz \
   --init '{ }' --burn-cap 3 &
   tezos-client bake for bootstrap1

   # as usual you can check the tezos-client manual
   tezos-client sapling man

   # generate two shielded keys for Alice and Bob and use them for the shielded-tez contract
   # the memo size has to be indicated
   tezos-client sapling gen key alice
   tezos-client sapling use key alice for contract shielded-tez --memo-size 8
   tezos-client sapling gen key bob
   tezos-client sapling use key bob for contract shielded-tez --memo-size 8

   # generate an address for Alice to receive shielded tokens.
   tezos-client sapling gen address alice
   zet1AliceXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX # Alice's address


   # shield 10 tez from bootstrap1 to alice
   tezos-client sapling shield 10 from bootstrap1 to zet1AliceXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX using shielded-tez --burn-cap 2 &
   tezos-client bake for bootstrap1
   tezos-client sapling get balance for alice in contract shielded-tez

   # generate an address for Bob to receive shielded tokens.
   tezos-client sapling gen address bob
   zet1BobXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX # Bob's address

   # forge a shielded transaction from alice to bob that is saved to a file
   tezos-client sapling forge transaction 10 from alice to zet1BobXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX using shielded-tez

   # submit the shielded transaction from any transparent account
   tezos-client sapling submit sapling_transaction from bootstrap2 using shielded-tez --burn-cap 1 &
   tezos-client bake for bootstrap1
   tezos-client sapling get balance for bob in contract shielded-tez

   # unshield from bob to any transparent account
   tezos-client sapling unshield 10 from bob to bootstrap1 using shielded-tez --burn-cap 1
   ctrl+z # to put the process in background
   tezos-client bake for bootstrap1
   fg # to put resume the transfer
