"""Run the real nodo Gateway on a TLS port, for the integration test of celaut-client.

Run from any directory, with a nodo checkout on the path (nodo dev e3d12301 was used):

    PYTHONPATH=<nodo> python3 nodo_gateway.py [--free-clients N]

The script loads the example config of nodo in a temporary directory (as the tests of
nodo do), makes the identity and the TLS certificate, and serves `Gateway()` with
`server_credentials()` on 127.0.0.1 and a free port, as `src/serve.py` does. It does not
open a firewall port, does not start the manager thread, and starts no service, so
it needs no root and no KVM.

It prints one line, `READY <port> <peer_id>`, and serves until it is stopped. With
`--free-clients` it also prints `POW_REQUIRED difficulty=<n>` when it asks for a proof of
work, and `CLIENT_CREATED` when it makes a client.

`--free-clients N` sets `free_tier.MAX_WORK_FREE_CLIENTS_PER_DIFFICULTY`. With a small N and
N clients already made, the node asks for a proof of work.
"""
import sys
import threading
from concurrent import futures

from tests.config_bootstrap import load_example_config

load_example_config()

import grpc  # noqa: E402

from protos import celaut_pb2, celaut_pb2_grpc  # noqa: E402
from src.gateway.gateway import Gateway  # noqa: E402
from src.identity.grpc_transport import server_credentials  # noqa: E402
from src.database import migrate  # noqa: E402
from src.identity.node_identity import get_node_public_key_hex  # noqa: E402


def main():
    # The schema that the setup scripts of nodo make (`nodo migrate`). Before the
    # first call that opens the database.
    migrate.migrate()
    if "--free-clients" in sys.argv:
        import src.gateway.gateway as gateway_module
        import src.manager.manager as manager
        per_difficulty = int(sys.argv[sys.argv.index("--free-clients") + 1])
        manager.max_work_free_clients_per_difficulty = lambda: per_difficulty
        original = gateway_module.generate_client_or_pow_required

        def reporting(**kwargs):
            answer = original(**kwargs)
            if isinstance(answer, celaut_pb2.PoWRequired):
                print(f"POW_REQUIRED difficulty={answer.difficulty}", flush=True)
            else:
                print("CLIENT_CREATED", flush=True)
            return answer

        gateway_module.generate_client_or_pow_required = reporting
    server = grpc.server(futures.ThreadPoolExecutor(max_workers=8))
    celaut_pb2_grpc.add_GatewayServicer_to_server(Gateway(), server=server)
    port = server.add_secure_port("127.0.0.1:0", server_credentials())
    server.start()
    print(f"READY {port} {get_node_public_key_hex()}", flush=True)
    threading.Event().wait()


main()
