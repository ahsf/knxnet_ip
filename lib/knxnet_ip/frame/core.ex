defmodule KNXnetIP.Frame.Core do
  @moduledoc """
  Implementation of the KNXnet/IP Core specification (document 3/8/2)
  """

  alias KNXnetIP.Frame.Tunnelling

  @tunnel_connection 0x04
  @e_no_error 0x00
  @e_connection_id 0x21
  @e_data_connection 0x26
  @e_knx_connection 0x27
  @ipv4_udp 0x01
  @connect_request_timeout 10_000
  @connectionstate_request_timeout 10_000

  def constant(:ipv4_udp), do: @ipv4_udp
  def constant(:tunnel_connection), do: @tunnel_connection
  def constant(@tunnel_connection), do: :tunnel_connection
  def constant(:e_no_error), do: @e_no_error
  def constant(@e_no_error), do: :e_no_error
  def constant(:e_connection_id), do: @e_connection_id
  def constant(@e_connection_id), do: :e_connection_id
  def constant(:e_data_connection), do: @e_data_connection
  def constant(@e_data_connection), do: :e_data_connection
  def constant(:e_knx_connection), do: @e_knx_connection
  def constant(@e_knx_connection), do: :e_knx_connection
  def constant(:connect_request_timeout), do: @connect_request_timeout
  def constant(:connectionstate_request_timeout), do: @connectionstate_request_timeout

  defmodule HostProtocolAddressInformation do
    defstruct host_protocol_code: :ipv4_udp,
      ip_address: {127, 0, 0, 1},
      port: nil
  end

  defmodule ConnectionRequestInformation do
    defstruct connection_type: nil,
      connection_data: nil
  end

  defmodule ConnectionResponseDataBlock do
    defstruct connection_type: nil,
      connection_data: nil
  end

  defmodule ConnectRequest do
    alias KNXnetIP.Frame.Core
    defstruct control_endpoint: %Core.HostProtocolAddressInformation{},
      data_endpoint: %Core.HostProtocolAddressInformation{},
      connection_request_information: %Core.ConnectionRequestInformation{}
  end

  defmodule ConnectResponse do
    alias KNXnetIP.Frame.Core
    defstruct communication_channel_id: nil,
      status: nil,
      data_endpoint: %Core.HostProtocolAddressInformation{},
      connection_response_data_block: %Core.ConnectionResponseDataBlock{}
  end

  defmodule ConnectionstateRequest do
    alias KNXnetIP.Frame.Core
    defstruct communication_channel_id: nil,
      control_endpoint: %Core.HostProtocolAddressInformation{}
  end

  defmodule ConnectionstateResponse do
    defstruct communication_channel_id: nil,
      status: nil
  end

  defmodule DisconnectRequest do
    alias KNXnetIP.Frame.Core
    defstruct communication_channel_id: nil,
      control_endpoint: %Core.HostProtocolAddressInformation{}
  end

  defmodule DisconnectResponse do
    defstruct communication_channel_id: nil,
      status: nil
  end

  def encode_connect_request(req) do
    control_endpoint = encode_hpai(req.control_endpoint)
    data_endpoint = encode_hpai(req.data_endpoint)
    cri = encode_cri(req.connection_request_information)
    control_endpoint <> data_endpoint <> cri
  end

  def encode_connect_response(resp) do
    status = constant(resp.status)
    data_endpoint = encode_hpai(resp.data_endpoint)
    crd = encode_crd(resp.connection_response_data_block)
    <<resp.communication_channel_id, status>> <> data_endpoint <> crd
  end

  def encode_connectionstate_request(cr) do
    control_endpoint = encode_hpai(cr.control_endpoint)
    <<cr.communication_channel_id::8, 0x00::8>> <> control_endpoint
  end

  def encode_connectionstate_response(cr) do
    <<cr.communication_channel_id, constant(cr.status)>>
  end

  def encode_disconnect_request(req) do
    control_endpoint = encode_hpai(req.control_endpoint)
    <<req.communication_channel_id, 0x00>> <> control_endpoint
  end

  def encode_disconnect_response(resp) do
    <<resp.communication_channel_id, constant(resp.status)>>
  end

  defp encode_hpai(%HostProtocolAddressInformation{} = hpai) do
    length = 0x08
    host_protocol_code = constant(:ipv4_udp)
    {ip1, ip2, ip3, ip4} = hpai.ip_address
    <<
      length, host_protocol_code,
      ip1, ip2, ip3, ip4,
      hpai.port :: 16
    >>
  end

  defp encode_cri(%ConnectionRequestInformation{} = cri) do
    connection_data = case cri.connection_type do
      :tunnel_connection -> Tunnelling.encode_cri(cri.connection_data)
    end
    length = 2 + byte_size(connection_data)
    connection_type = constant(cri.connection_type)
    <<length, connection_type>> <> connection_data
  end

  defp encode_crd(%ConnectionResponseDataBlock{} = crd) do
    connection_data = case crd.connection_type do
      :tunnel_connection -> Tunnelling.encode_crd(crd.connection_data)
    end
    length = 2 + byte_size(connection_data)
    connection_type = constant(crd.connection_type)
    <<length, connection_type>> <> connection_data
  end

  def decode_connect_request(
      <<
        _control_length, control_hpai::binary-size(7),
        _data_length, data_hpai::binary-size(7),
        _cri_length, cri::binary-size(3)
      >>) do
    with {:ok, control_endpoint} <- decode_hpai(control_hpai),
         {:ok, data_endpoint} <- decode_hpai(data_hpai),
         {:ok, cri} <- decode_connection_request_information(cri) do
      connect_request = %ConnectRequest{
        control_endpoint: control_endpoint,
        data_endpoint: data_endpoint,
        connection_request_information: cri,
      }
      {:ok, connect_request}
    end
  end

  def decode_connect_request(frame),
    do: {:error, {:frame_decode_error, frame, "invalid format of connect request frame"}}

  def decode_connect_response(
      <<
        communication_channel_id, @e_no_error,
        _data_length, data_hpai::binary-size(7),
        _crd_length, crd::binary-size(3)
      >>) do
    with {:ok, data_endpoint} <- decode_hpai(data_hpai),
         {:ok, crd} <- decode_connection_response_data_block(crd) do
      connect_response = %ConnectResponse{
        communication_channel_id: communication_channel_id,
        status: :e_no_error,
        data_endpoint: data_endpoint,
        connection_response_data_block: crd
      }
      {:ok, connect_response}
    end
  end

  def decode_connect_response(<<communication_channel_id, status>>) do
    case constant(status) do
      nil -> {:error, {:frame_decode_error, status, "unsupported connection status code"}}
      status ->
        connect_response = %ConnectResponse{
          communication_channel_id: communication_channel_id,
          status: status
        }
        {:ok, connect_response}
    end
  end

  def decode_connect_response(connect_response),
    do: {:error, {:frame_decode_error, connect_response, "invalid format of connect response frame"}}

  def decode_connectionstate_request(
      <<
        communication_channel_id, _reserved,
        _control_length, control_hpai::binary
      >>) do
    with {:ok, control_endpoint} <- decode_hpai(control_hpai) do
      connectionstate_request = %ConnectionstateRequest{
        communication_channel_id: communication_channel_id,
        control_endpoint: control_endpoint
      }
      {:ok, connectionstate_request}
    end
  end

  def decode_connectionstate_response(<<communication_channel_id, status>>) do
    case constant(status) do
      nil -> {:error, {:frame_decode_error, status, "unsupported connection status code"}}
      status ->
        connectionstate_response = %ConnectionstateResponse{
          communication_channel_id: communication_channel_id,
          status: status
        }
        {:ok, connectionstate_response}
    end
  end

  def decode_disconnect_request(
      <<
        communication_channel_id, _reserved,
        _control_length, control_hpai::binary
      >>) do
    with {:ok, control_endpoint} <- decode_hpai(control_hpai) do
      disconnect_request = %DisconnectRequest{
        communication_channel_id: communication_channel_id,
        control_endpoint: control_endpoint
      }
      {:ok, disconnect_request}
    end
  end

  def decode_disconnect_response(<<communication_channel_id, status>>) do
    case constant(status) do
      nil -> {:error, {:frame_decode_error, status, "unsupported connection status code"}}
      status ->
        disconnect_response = %DisconnectResponse{
          communication_channel_id: communication_channel_id,
          status: status
        }
        {:ok, disconnect_response}
    end
  end

  defp decode_hpai(<<@ipv4_udp, data::binary>>) do
    with {:ok, ip, port} <- decode_ip_and_port(data) do
      hpai = %HostProtocolAddressInformation{
        host_protocol_code: :ipv4_udp,
        ip_address: ip,
        port: port
      }
      {:ok, hpai}
    end
  end

  defp decode_hpai(frame), do: {:error, {:frame_decode_error, frame, "unsupported host protocol code"}}

  defp decode_ip_and_port(<<ip1, ip2, ip3, ip4, port::16>>) do
    {:ok, {ip1, ip2, ip3, ip4}, port}
  end

  defp decode_ip_and_port(frame), do: {:error, {:frame_decode_error, frame, "could not decode ip and port"}}

  defp decode_connection_request_information(<<@tunnel_connection, data::binary>>) do
    with {:ok, connection_data} <- Tunnelling.decode_connection_request_data(data) do
      cri = %ConnectionRequestInformation{
        connection_type: :tunnel_connection,
        connection_data: connection_data,
      }
      {:ok, cri}
    end
  end

  defp decode_connection_request_information(<<connection_type, _data::binary>>) do
    {:error, {:frame_decode_error, connection_type, "unsupported connection type"}}
  end

  defp decode_connection_response_data_block(<<@tunnel_connection, data::binary>>) do
    with {:ok, connection_data} = Tunnelling.decode_connection_response_data(data) do
      crd = %ConnectionResponseDataBlock{
        connection_type: :tunnel_connection,
        connection_data: connection_data,
      }
      {:ok, crd}
    end
  end
end
