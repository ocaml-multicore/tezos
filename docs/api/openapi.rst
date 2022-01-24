OpenAPI Specification
=====================

`OpenAPI <https://swagger.io/specification/>`_ is a specification format for REST APIs.
This format is supported by several tools, such as
`Swagger UI <https://swagger.io/tools/swagger-ui/>`_ which allows you to browse
a specification and perform API calls from your browser.
Several code generators also exist to generate API libraries for various
programming languages.

Shell RPCs
----------

.. Note: the links currently point to master because no release branch
.. currently has the OpenAPI specification.
..
.. As soon as an actual release has this specification we should update
.. this section and the next one. The idea would be to link to all release tags,
.. and have an additional link at the top to the latest-release branch.
.. We'll probably remove the link to the specification for version 7.5 at this point
.. since it does not make sense to keep it in master forever.

The node provide some RPCs which are independent of the protocol.
Their OpenAPI specification can be found at:

- `rpc-openapi.json (version 11.0) <https://gitlab.com/tezos/tezos/-/blob/master/docs/api/rpc-openapi.json>`_

.. TODO tezos/tezos#2170: add/remove section(s)

Hangzhou RPCs
-------------

The OpenAPI specification for RPCs which are specific to the Hangzhou (``PtHangz2``)
protocol can be found at:

- `hangzhou-openapi.json (version 11.0) <https://gitlab.com/tezos/tezos/-/blob/master/docs/api/hangzhou-openapi.json>`_

The OpenAPI specification for RPCs which are related to the mempool
and specific to the Hangzhou protocol can be found at:

- `hangzhou-mempool-openapi.json (version 11.0) <https://gitlab.com/tezos/tezos/-/blob/master/docs/api/hangzhou-mempool-openapi.json>`_

How to Generate
---------------

To generate the above files, run the ``src/bin_openapi/generate.sh`` script
from the root of the Tezos repository.
It will start a sandbox node, activate the protocol,
get the RPC specifications from this node and convert them to OpenAPI specifications.

To generate the OpenAPI specification for the RPCs provided by a specific protocol,
update the following variables in :src:`src/bin_openapi/generate.sh`:

```sh
protocol_hash=ProtoALphaALphaALphaALphaALphaALphaALphaALphaDdp3zK
protocol_parameters=src/proto_alpha/parameters/sandbox-parameters.json
protocol_name=alpha
```

For ``protocol_hash``, use the value defined in ``TEZOS_PROTOCOL``.


How to Test
-----------

You can test OpenAPI specifications using `Swagger Editor <https://editor.swagger.io/>`_
to check for syntax issues (just copy-paste ``rpc-openapi.json`` into it or open
it from menu ``File > Import file``).

You can run `Swagger UI <https://swagger.io/tools/swagger-ui/>`_ to get an interface
to browse the API (replace ``xxxxxx`` with the directory where ``rpc-openapi.json`` is,
and ``rpc-openapi.json`` by the file you want to browse)::

    docker pull swaggerapi/swagger-ui
    docker run -p 8080:8080 -e SWAGGER_JSON=/mnt/rpc-openapi.json -v xxxxxx:/mnt swaggerapi/swagger-ui

Then `open it in your browser <https://localhost:8080>`_.
