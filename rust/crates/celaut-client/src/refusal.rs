//! Why a node refuses a request (milestone M4, the feedback of a rejected launch).
//!
//! A node (nodo) refuses a quote or a start with a gRPC error whose message is free text:
//! a Python exception. There is no error code. This module reads the texts that nodo
//! writes and says what they mean, so that the app can tell the user the reason and what
//! to do. The texts are from nodo `src/gateway` (`estimated_cost_iterable.py`,
//! `launch_service.py`, `client_gate.py`, `abstract_input_service_iterable.py`),
//! `src/utils/activity_window.py`, `src/utils/network_policy.py` and
//! `src/virtualizers/architecture.py`. A text that this module does not know gives `None`:
//! the caller then shows the text as it is.
//!
//! The match is on lowercase fragments of the text. If nodo changes a text, the reason is
//! not found and the app shows the original text, so a change in nodo cannot give a wrong
//! reason, only a less precise one.

/// The reason that a node does not run a service.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum Refusal {
    /// The node does not know the client id of the app (it forgot it, or never made it).
    ClientUnknown,
    /// The node limits the calls of this client for a time.
    RateLimited,
    /// The node is outside the hours that its operator set (`activity_window`).
    NodeClosed,
    /// The node has not enough free resources for the service now.
    NoRoom,
    /// The node does not have the service and the request does not carry it.
    ServiceMissing,
    /// The policy of the node (a list of domains that the operator allows or refuses)
    /// does not allow the networks that the service declares.
    PolicyRefused,
    /// The service is for an architecture that the node does not run.
    UnsupportedArchitecture,
    /// The request came back to a node that already has it, or it passed the depth limit.
    RecursionLimit,
    /// The client has not enough balance on the node for the start. The app finds this
    /// itself, before it asks the node to start.
    InsufficientCredit,
    /// The node tried to start the service and could not, for a reason that it does not
    /// say as one of the above.
    LaunchFailed,
}

/// The phrases of each reason, in lowercase. The order of the list matters: a launch that
/// fails after other attempts carries the reason of each attempt in one text, so the
/// specific reasons come before `LaunchFailed`.
const PHRASES: [(Refusal, &[&str]); 9] = [
    (
        Refusal::ClientUnknown,
        &["requires a client_id minted by generateclient"],
    ),
    (Refusal::RateLimited, &["temporarily quarantined"]),
    (
        Refusal::NodeClosed,
        &[
            "outside its activity window",
            "is not accepting new work",
        ],
    ),
    (
        Refusal::NoRoom,
        &[
            "cannot run the service right now",
            "rejected due to insufficient resources",
        ],
    ),
    (
        Refusal::ServiceMissing,
        &[
            "not on local registry",
            "does not have the service",
            "on registry",
        ],
    ),
    (
        Refusal::PolicyRefused,
        &["network policy:", "refuses to run a service"],
    ),
    (
        Refusal::UnsupportedArchitecture,
        &["unsupported architecture"],
    ),
    (
        Refusal::RecursionLimit,
        &[
            "recursion loop",
            "recursion depth",
            "recursion token",
        ],
    ),
    (
        Refusal::LaunchFailed,
        &[
            "unable to launch service",
            "error charging",
            "failed to set initial_mu",
        ],
    ),
];

/// The reason in the text of a refusal, or `None` if the text says none that this module
/// knows.
pub fn classify(text: &str) -> Option<Refusal> {
    let lower = text.to_ascii_lowercase();
    PHRASES
        .iter()
        .find(|(_, phrases)| phrases.iter().any(|p| lower.contains(p)))
        .map(|(reason, _)| *reason)
}

/// The message of a gRPC error as nodo wrote it, with the wrapper of the transport
/// removed. tonic shows an error as
/// `status: Unknown, message: "Exception calling application: <text>", details: [], ...`.
pub fn message_of(text: &str) -> String {
    let mut body = text;
    if let Some(start) = text.find("message: \"") {
        let rest = &text[start + "message: \"".len()..];
        body = match rest.find("\", details:") {
            Some(end) => &rest[..end],
            None => rest.trim_end_matches('"'),
        };
    }
    let body = body
        .replace("\\n", "\n")
        .replace("\\\"", "\"")
        .replace("\\\\", "\\");
    body.strip_prefix("Exception calling application: ")
        .unwrap_or(&body)
        .trim()
        .to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    /// The error that tonic shows for an exception of nodo.
    fn grpc(message: &str) -> String {
        format!(
            "status: Unknown, message: \"Exception calling application: {message}\", details: [], metadata: MetadataMap {{ headers: {{}} }}"
        )
    }

    #[test]
    fn each_text_of_nodo_gives_its_reason() {
        let cases = [
            (
                "This RPC requires a client_id minted by GenerateClient first. Wrong or missing client_id: 'x'",
                Refusal::ClientUnknown,
            ),
            (
                "Client abc is calling too fast and is temporarily quarantined.",
                Refusal::RateLimited,
            ),
            ("This node is not accepting new work.", Refusal::NodeClosed),
            (
                "This node is outside its activity window: it accepts new work between 09:00 and 18:00 local time (SCHEDULE in config.yaml).",
                Refusal::NodeClosed,
            ),
            (
                "Unable to launch service ab12: This node is outside its activity window: it accepts new work between 09:00 and 18:00 local time (SCHEDULE in config.yaml).",
                Refusal::NodeClosed,
            ),
            (
                "This node cannot run the service right now: not enough memory.",
                Refusal::NoRoom,
            ),
            (
                "Service ab12 not on local registry.",
                Refusal::ServiceMissing,
            ),
            (
                "This node does not have the service ab12, and the request does not contain it.",
                Refusal::ServiceMissing,
            ),
            (
                "No service ab12 on registry",
                Refusal::ServiceMissing,
            ),
            (
                "Network policy: this node refuses to run a service for service ab12 that reaches 'example.org'.\n  declared networks:\n    #1: example.org",
                Refusal::PolicyRefused,
            ),
            (
                "Unsupported architecture 'riscv64'.\nSupported architectures: ['linux/amd64', 'linux/arm64'].",
                Refusal::UnsupportedArchitecture,
            ),
            (
                "Block recursion loop, recursion token: t",
                Refusal::RecursionLimit,
            ),
            (
                "Unable to launch service ab12. Attempt details: local preflight: x | peer p: Exception: y",
                Refusal::LaunchFailed,
            ),
            (
                "Unable to launch service ab12: no eligible local executor or peer was available at this time.",
                Refusal::LaunchFailed,
            ),
            ("Launch service error charging abc", Refusal::LaunchFailed),
        ];
        for (text, expected) in cases {
            assert_eq!(classify(text), Some(expected), "{text}");
            assert_eq!(classify(&grpc(text)), Some(expected), "wrapped: {text}");
        }
    }

    #[test]
    fn a_launch_that_failed_for_a_known_reason_gives_that_reason() {
        let text = "Unable to launch service ab12. Attempt details: local preflight: This node cannot run the service right now: not enough memory.";
        assert_eq!(classify(text), Some(Refusal::NoRoom));
    }

    #[test]
    fn a_text_that_nodo_did_not_write_before_gives_no_reason() {
        for text in ["", "something broke", "status: Unavailable, message: \"connection reset\""] {
            assert_eq!(classify(text), None, "{text}");
        }
    }

    #[test]
    fn the_case_of_the_text_does_not_matter() {
        assert_eq!(
            classify("THIS NODE IS NOT ACCEPTING NEW WORK."),
            Some(Refusal::NodeClosed)
        );
    }

    #[test]
    fn the_wrapper_of_the_transport_is_removed() {
        assert_eq!(
            message_of(&grpc("This node is not accepting new work.")),
            "This node is not accepting new work."
        );
        // Line breaks and quotes that the debug format escaped come back.
        assert_eq!(
            message_of(&grpc("Network policy: it refuses '\\\"x\\\"'.\\n  rule: r")),
            "Network policy: it refuses '\"x\"'.\n  rule: r"
        );
        // A text with no wrapper stays as it is.
        assert_eq!(message_of("plain text"), "plain text");
        assert_eq!(
            message_of("Exception calling application: plain"),
            "plain"
        );
        assert_eq!(message_of(""), "");
    }
}
