defmodule KNXnetIP do
  @moduledoc """
  KNXnetIP has three main components for translating messages between the
  KNXnet/IP wire protocol and Elixir datatypes:

    - `KNXnetIP.Frame`: Codecs for KNXnet/IP UDP frame structures, which are
      used to implement the KNXnet/IP services. KNXnet/IP Core services implement
      connection management, while the Tunnelling services carry KNX telegrams
      to and from the KNX bus.
    - `KNXnetIP.Telegram`: Codecs for KNX telegrams. KNX telegrams contain data
      from all layers of the KNX application stack, but KNXnetIP only concerns
      itself with data from the application layer.
    - `KNXnetIP.Datapoint`: Codecs for KNX datapoints. Translates datapoints,
      which are encoded as KNX datatypes, to Elixir datatypes.

  In addition to the codec functionality, the `KNXnetIP.Tunnel` module provides
  a behaviour for a KNXnet/IP client. It handles for establishing and
  maintaining a KNXnet/IP connection, and invokes the callback module when
  telegrams arrives from the KNX bus.
  """
end
