{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE NumericUnderscores #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeFamilies #-}
{-# OPTIONS_GHC -Wno-orphans #-}

module OpenTelemetry.Exporter.OTLP.Config (
  -- * Configuring the exporter
  OTLPExporterConfig (..),
  CompressionFormat (..),
  Protocol (..),
  loadExporterEnvironmentVariables,

  -- ** Default local endpoints
  otlpExporterHttpEndpoint,
  otlpExporterGRpcEndpoint,

  -- ** Default timeout
  otlpExporterTimeoutMilli,
) where

import Control.Monad.IO.Class
import qualified Data.ByteString.Char8 as C
import qualified Data.CaseInsensitive as CI
import Data.Char (toLower)
import qualified Data.HashMap.Strict as H
import qualified Data.Text.Encoding as T
import Lens.Micro
import Network.HTTP.Types.Header
import qualified OpenTelemetry.Baggage as Baggage
import OpenTelemetry.Environment
import System.Environment
import qualified System.IO as IO
import Text.Read (readMaybe)


data OTLPExporterConfig = OTLPExporterConfig
  { otlpEndpoint :: Maybe String
  , otlpTracesEndpoint :: Maybe String
  , otlpMetricsEndpoint :: Maybe String
  , otlpInsecure :: Bool
  , otlpSpanInsecure :: Bool
  , otlpMetricInsecure :: Bool
  , otlpCertificate :: Maybe FilePath
  , otlpTracesCertificate :: Maybe FilePath
  , otlpMetricCertificate :: Maybe FilePath
  , otlpHeaders :: Maybe [Header]
  , otlpTracesHeaders :: Maybe [Header]
  , otlpMetricsHeaders :: Maybe [Header]
  , otlpCompression :: Maybe CompressionFormat
  , otlpTracesCompression :: Maybe CompressionFormat
  , otlpMetricsCompression :: Maybe CompressionFormat
  , otlpTimeout :: Maybe Int
  -- ^ Measured in milliseconds.
  , otlpTracesTimeout :: Maybe Int
  -- ^ Measured in milliseconds.
  , otlpMetricsTimeout :: Maybe Int
  -- ^ Measured in milliseconds.
  , otlpProtocol :: Maybe Protocol
  , otlpTracesProtocol :: Maybe Protocol
  , otlpMetricsProtocol :: Maybe Protocol
  }


loadExporterEnvironmentVariables :: (MonadIO m) => m OTLPExporterConfig
loadExporterEnvironmentVariables = liftIO $ do
  OTLPExporterConfig
    <$> lookupEnv "OTEL_EXPORTER_OTLP_ENDPOINT"
    <*> lookupEnv "OTEL_EXPORTER_OTLP_TRACES_ENDPOINT"
    <*> lookupEnv "OTEL_EXPORTER_OTLP_METRICS_ENDPOINT"
    <*> lookupBooleanEnv "OTEL_EXPORTER_OTLP_INSECURE"
    <*> lookupBooleanEnv "OTEL_EXPORTER_OTLP_SPAN_INSECURE"
    <*> lookupBooleanEnv "OTEL_EXPORTER_OTLP_METRIC_INSECURE"
    <*> lookupEnv "OTEL_EXPORTER_OTLP_CERTIFICATE"
    <*> lookupEnv "OTEL_EXPORTER_OTLP_TRACES_CERTIFICATE"
    <*> lookupEnv "OTEL_EXPORTER_OTLP_METRICS_CERTIFICATE"
    <*> (fmap decodeHeaders <$> lookupEnv "OTEL_EXPORTER_OTLP_HEADERS")
    <*> (fmap decodeHeaders <$> lookupEnv "OTEL_EXPORTER_OTLP_TRACES_HEADERS")
    <*> (fmap decodeHeaders <$> lookupEnv "OTEL_EXPORTER_OTLP_METRICS_HEADERS")
    <*> (traverse readCompressionFormat =<< lookupEnv "OTEL_EXPORTER_OTLP_COMPRESSION")
    <*> (traverse readCompressionFormat =<< lookupEnv "OTEL_EXPORTER_OTLP_TRACES_COMPRESSION")
    <*> (traverse readCompressionFormat =<< lookupEnv "OTEL_EXPORTER_OTLP_METRICS_COMPRESSION")
    <*> (traverse readTimeout =<< lookupEnv "OTEL_EXPORTER_OTLP_TIMEOUT")
    <*> (traverse readTimeout =<< lookupEnv "OTEL_EXPORTER_OTLP_TRACES_TIMEOUT")
    <*> (traverse readTimeout =<< lookupEnv "OTEL_EXPORTER_OTLP_METRICS_TIMEOUT")
    <*> (traverse readProtocol =<< lookupEnv "OTEL_EXPORTER_OTLP_PROTOCOL")
    <*> (traverse readProtocol =<< lookupEnv "OTEL_EXPORTER_OTLP_TRACES_PROTOCOL")
    <*> (traverse readProtocol =<< lookupEnv "OTEL_EXPORTER_OTLP_METRICS_PROTOCOL")
  where
    decodeHeaders hsString = case Baggage.decodeBaggageHeader $ C.pack hsString of
      Left _ -> mempty
      Right baggageFmt ->
        (\(k, v) -> (CI.mk $ Baggage.tokenValue k, T.encodeUtf8 $ Baggage.value v)) <$> H.toList (Baggage.values baggageFmt)


{- |
The OpenTelemetry Protocol Compression Format.
-}
data CompressionFormat
  = None
  | GZip


{- |
Internal helper.
Read the `CompressionFormat` from a `String`.
Defaults to `None` for unsupported values.
-}
readCompressionFormat :: (MonadIO m) => String -> m CompressionFormat
readCompressionFormat compressionFormat =
  compressionFormat & fmap toLower & \case
    "gzip" -> pure GZip
    "none" -> pure None
    _ -> do
      putWarningLn $ "Warning: unsupported compression format '" <> compressionFormat <> "'"
      pure None


{- |
The OpenTelemetry Protocol. Either HTTP/Protobuf or gRPC.

Note: HTTP/JSON will likely be supported eventually, but not yet.
-}
data Protocol {- HttpJson | -}
  = HttpProtobuf
  | GRpc


{- |
Internal helper.
Read a `Protocol` from a `String`.
Defaults to `HttpProtobuf` for unsupported values.
-}
readProtocol :: (MonadIO m) => String -> m Protocol
readProtocol protocol =
  protocol & fmap toLower & \case
    "grpc" -> pure GRpc
    "http/protobuf" -> pure HttpProtobuf
    _ -> do
      putWarningLn $ "Warning: unsupported protocol '" <> protocol <> "'"
      pure HttpProtobuf


{- |
Internal helper.
Read a timeout from a `String`.
-}
readTimeout :: (MonadIO m) => String -> m Int
readTimeout timeout =
  case readMaybe timeout of
    Just timeoutInt | timeoutInt >= 0 -> pure timeoutInt
    _otherwise -> do
      putWarningLn $ "Warning: unsupported timeout '" <> timeout <> "'"
      pure otlpExporterTimeoutMilli


{- |
Internal helper.
The default OTLP timeout in milliseconds.
-}
otlpExporterTimeoutMilli :: Int
otlpExporterTimeoutMilli = 10_000


{- |
The default OTLP HTTP endpoint.
-}
otlpExporterHttpEndpoint :: C.ByteString
otlpExporterHttpEndpoint = "http://localhost:4318"


{- |
The default OTLP gRPC endpoint.
-}
otlpExporterGRpcEndpoint :: C.ByteString
otlpExporterGRpcEndpoint = "http://localhost:4317"


{- |
Internal helper.
Print a warning to stderr
-}
putWarningLn :: (MonadIO m) => String -> m ()
putWarningLn = liftIO . IO.hPutStrLn IO.stderr
