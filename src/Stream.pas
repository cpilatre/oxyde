unit Stream;

{$MODE Delphi}

{ Stream : Fournie une version très light de gestion des sockets
  Date : Juin 2000
  Auteur : Claude Pilatre }

interface

uses
  Classes, SysUtils, Windows, WinSock;

const
  SD_RECEIVE = 0;
  SD_SEND = 1;
  SD_BOTH = 2;

  SOCKET_ERROR = -1;
  NO_ERROR = 0;

type
  { Indique dans quel état est la socket. }
  TSocketStatus = (ssInactive,  { Aucune socket n'a été créée }
                   ssListen,    { La socket est créée et est en écoute }
                   ssConnect,   { On est connecté à un serveur }
                   ssAccepted); { Un client a été accepté (Il s'agit de la socket de travail) }


  { ___ Classe de base ___ }

  { Elle ne permet pas de se connecter mais simplement de lire ou d'écrire. }
  CustomSocket = class(TObject)
  protected
    Sock: TSocket;
    fSockAddr: TSockAddrIn;
    fStatus: TSocketStatus;
  public
    property Status: TSocketStatus read fStatus;
    property SockAddr: TSockAddrIn read fSockAddr;

    { Lit des données dans la socket et les stocke dans Buffer. Au retour
      le nombre d'octet réellement lus est renvoyé. }
    function ReadData(Buffer: Pointer; SizeOfBuffer: DWORD): Integer;
    { Ecrit les SizeOfBuffer octets contenus de buffer dans la socket.
      Au retour le nombre d'octet réellement écrits est renvoyé. }
    function WriteData(Buffer: Pointer; SizeOfBuffer: DWORD): Integer;
    { Transmet un fichier complet et une entête }
    function TransmitFile(hFile: THandle; lpTransmitBuffers: PTransmitFileBuffers): Boolean;
    { Renvoie la taille en octet des données disponibles dans la socket. }
    function getDataSize(Seconds: DWORD): Integer;
    { Fait un shutdown et un close sur la socket }
    function Shutdown(How: Integer): Integer;
    { Ferme la socket }
    function reStart: Integer;
    constructor Create;
    { Ce constructeur est utilisé par la classe ConnectSocket lorsqu'elle accepte une
      connexion cliente. }
    constructor ConnectedTo(Sock_io: TSocket; sout: PSockAddrIn);
    destructor Destroy; override;
  end;

  { ___ Classe de connection ___ }

  { Elle permet de créer une socket serveur, d'accepter des connections ou
    de se connecter à un serveur }
  ConnectSocket = class(CustomSocket)
  private
    fHost: PHostEnt;
  public
    property Host: PHostEnt read fHost;

    { Création d'une socket d'écoute sur l'adresse passée en paramètre.
      Cela permet sur des machines multi-interface de choisir la carte réseau. }
    function CreateSocketServerEx(NetAddr: TInAddr; nPort: WORD; nListen: Integer): Integer;
    { Création d'une socket d'écoute sur une interface définie par le système.
      Appel en interne CreateSocketServerEx avec INADDR_ANY. }
    function CreateSocketServer(nPort: WORD; nListen: Integer): Integer;
    { Création d'une socket d'écoute pour un service. Utilise en interne CreateSocketServerEx }
    function CreateSocketServiceEx(NetAddr: TInAddr; szName: PChar; nListen: Integer): Integer;
    { Création d'une socket d'écoute pour un service sur une interface choisie par le système.
      Utilise en interne CreateSocketServiceEx }
    function CreateSocketService(szName: PChar; nListen: Integer): Integer;
    { Permet de ce connecter à un serveur. }
    function ConnectHost(szHostName: PChar; nPort: WORD): Integer;
    { Attend la connexion d'un client sur la socket que l'on a créée avec un
      CreateSocketServer(Ex). Elle renvoie un objet de type CustomSocket qui sera à
      la charge du programme appelant (Shutdown et destruction en particulier). }
    function AcceptHost: CustomSocket;

  end;

  { Démarre l'API socket
    wVersion = MAKEWORD(Majeur, Mineur) ou $101 par exemple }
  function StartSocket(wVersion: WORD): Integer;
  { Arrête l'API socket }
  function StopSocket: Integer;
  { Convertie le code renvoyer par WSAGetLastError en une chaine de caractère
    décrivant l'erreur (il s'agit de la description contenu dans le fichier WIN32.HLP). }
  function ConvertError(Error: Integer): string;

var
  { Cette variable globale contient des informations sur l'implémentation des sockets
    sous Windows }
  wsaData: TWSAData;

implementation

{ Demarre l'API Win Socket. Renvoie SOCKET_NO_ERROR (0) s'il n'y a pas d'erreur }

function StartSocket(wVersion: WORD): Integer;
begin
  Result := WSAStartup(wVersion, wsaData);
end;

{ Arrête l'API Win Socket. Renvoie NO_ERROR s'il n'y a pas d'erreur }

function StopSocket: Integer;
begin
  Result := WSACleanup();
end;

{ Conversion des codes d'erreurs en chaine de caractères.
  Les constantes en commentaires sont celles prises en compte par la fonction
  mais qui sont déjà définies au dessus. }

function ConvertError(Error: Integer): string;
begin
  case Error of
    { Si tout va bien }
    NO_ERROR : Result := 'No error';
    { WSAStartup }
    WSASYSNOTREADY     : Result := 'The underlying network subsystem is not ready for network communication.';
    WSAVERNOTSUPPORTED : Result := 'The version of Windows Sockets support requested is not provided by this particular Windows Sockets implementation.';
    WSAEINVAL          : Result := 'The Windows Sockets version specified by the application is not supported by this DLL.';
    { WSACleanup }
    WSANOTINITIALISED : Result := 'A successful WSAStartup must occur before using this function.';
    WSAENETDOWN       : Result := 'The Windows Sockets implementation has detected that the network subsystem has failed.';
    WSAEINPROGRESS    : Result := 'A blocking Windows Sockets operation is in progress.';
    { Socket }
    { WSANOTINITIALISED, WSAENETDOWN, WSAEINPROGRESS }
    WSAEAFNOSUPPORT    : Result := 'The specified address family is not supported.';
    WSAEMFILE          : Result := 'No more file descriptors are available.';
    WSAENOBUFS         : Result := 'No buffer space is available. The socket cannot be created.';
    WSAEPROTONOSUPPORT : Result := 'The specified protocol is not supported.';
    WSAEPROTOTYPE      : Result := 'The specified protocol is the wrong type for this socket.';
    WSAESOCKTNOSUPPORT : Result := 'The specified socket type is not supported in this address family.';
    { Bind }
    { WSANOTINITIALISED, WSAENETDOWN, WSAENOBUFS, WSAEINVAL, WSAEINPROGRESS, WSAEAFNOSUPPORT }
    WSAEADDRINUSE : Result := 'The specified address is already in use. (See the SO_REUSEADDR socket option under setsockopt.)';
    WSAEFAULT     : Result := 'The namelen argument is too small (less than the size of a struct sockaddr).';
    WSAENOTSOCK   : Result := 'The descriptor is not a socket.';
    { Listen }
    { WSANOTINITIALISED, WSAENETDOWN, WSAEADDRINUSE, WSAEINPROGRESS, WSAEINVAL, WSAEMFILE
      WSAENOBUFS, WSAENOTSOCK }
    WSAEISCONN    : Result := 'The socket is already connected.';
    WSAEOPNOTSUPP : Result := 'The referenced socket is not of a type that supports the listen operation.';
    { CloseSocket }
    { WSANOTINITIALISED, WSAENETDOWN, WSAENOTSOCK, WSAEINPROGRESS }
    WSAEINTR       : Result := 'The (blocking) call was canceled using WSACancelBlockingCall.';
    WSAEWOULDBLOCK : Result := 'The socket is marked as nonblocking and SO_LINGER is set to a nonzero timeout value.';
    { GetHostByName }
    { WSANOTINITIALISED, WSAENETDOWN, WSAEINPROGRESS, WSAEINTR }
    WSAHOST_NOT_FOUND : Result := 'Authoritative Answer Host not found.';
    WSATRY_AGAIN      : Result := 'Non-Authoritative Host not found, or SERVERFAIL.';
    WSANO_RECOVERY    : Result := 'Nonrecoverable errors: FORMERR, REFUSED, NOTIMP.';
    WSANO_DATA        : Result := 'Valid name, no data record of requested type.';
    { Accept }
    { WSANOTINITIALISED, WSAENETDOWN, WSAEINTR, WSAEINPROGRESS, WSAEINVAL, WSAEMFILE,
      WSAEFAULT, WSAENOTSOCK, WSAEOPNOTSUPP, WSAEWOULDBLOCK }
    { Recv }
    { WSANOTINITIALISED, WSAENETDOWN, WSAEINTR, WSAENOTSOCK, WSAEINPROGRESS, WSAEOPNOTSUPP
      WSAEWOULDBLOCK, WSAEINVAL }
    WSAENOTCONN     : Result := 'The socket is not connected.';
    WSAESHUTDOWN    : Result := 'The socket has been shut down; it is not possible to recv on a socket after shutdown has been invoked with how set to 0 or 2.';
    WSAEMSGSIZE     : Result := 'The datagram was too large to fit into the specified buffer and was truncated.';
    WSAECONNABORTED : Result := 'The virtual circuit was aborted due to timeout or other failure.';
    WSAECONNRESET   : Result := 'The virtual circuit was reset by the remote side.';
    { Select }
    { WSANOTINITIALISED, WSAENETDOWN, WSAEINVAL, WSAEINTR, WSAEINPROGRESS, WSAENOTSOCK }
    { Send }
    { WSANOTINITIALISED, WSAENETDOWN, WSAEINTR, WSAEINPROGRESS, WSAEFAULT, WSAENOBUFS,
      WSAENOTCONN, WSAENOTSOCK, WSAEOPNOTSUPP, WSAESHUTDOWN, WSAEWOULDBLOCK,
      WSAEMSGSIZE, WSAEINVAL, WSAECONNABORTED, WSAECONNRESET }
    WSAENETRESET    : Result := 'The connection has been broken due to the remote host resetting.';
    WSAEACCES       : Result := 'The requested address is a broadcast address, but the appropriate flag was not set.';
    WSAEHOSTUNREACH : Result := 'The remote host cannot be reached from this host at this time.';
    WSAETIMEDOUT    : Result := 'The connection has been dropped, because of a network failure or because the system on the other end went down without notice.';
    { Shutdown }
    { WSANOTINITIALISED, WSAENETDOWN, WSAEINVAL, WSAEINPROGRESS, WSAENOTCONN, WSAENOTSOCK }
  else
    Result := 'LastError() = $' + IntToHex(Error, $8);
  end;
end;

{__________________________________________________________________________________________

 CustomSocket
 __________________________________________________________________________________________}

constructor CustomSocket.Create;
begin
  fStatus := ssInactive;

  { Création de la socket }
  Sock := Socket(AF_INET, SOCK_STREAM, 0);
end;

constructor CustomSocket.ConnectedTo(Sock_io: TSocket; sout: PSockAddrIn);
begin
  Sock := Sock_io;
  if sout <> nil then
    CopyMemory(@fSockAddr, sout, SizeOf(fSockAddr));
  fStatus := ssAccepted;
end;

destructor CustomSocket.Destroy;
begin
  { Fermeture de la socket }
  CloseSocket(Sock);
end;

{ Permet de lire la socket }

function CustomSocket.ReadData(Buffer: Pointer; SizeOfBuffer: DWORD): Integer;
begin
  if fStatus in [ssConnect, ssAccepted] then
    { On peut s'attendre à lire des données dans la socket }
    Result := Recv(Sock, Buffer^, SizeOfBuffer, 0)
  else
    Result := 0;
end;

{ Permet d'écrire des données }

function CustomSocket.WriteData(Buffer: Pointer; SizeOfBuffer: DWORD): Integer;
begin
  if fStatus in [ssConnect, ssAccepted] then
    { On peut s'attendre à écrire correctement des données dans la socket }
    Result := Send(Sock, Buffer^, SizeOfBuffer, 0)
  else
    Result := 0;
end;

{ Transmet un fichier complet avec éventuellement un en-tête et une queue de message.
  Le paramètre lpTransmitBuffers peut être à nil pour n'envoyer que le fichier }

function CustomSocket.TransmitFile(hFile: THandle; lpTransmitBuffers: PTransmitFileBuffers): Boolean;
begin
  Result := WinSock.TransmitFile(Sock, hFile, 0, 0, nil, lpTransmitBuffers, 0);
end;

{ Renvoie la taille des données à venir }

function CustomSocket.getDataSize(Seconds: DWORD): Integer;
var
  Timeout: TTimeVal;
  Readfds: TFDSet;
begin
  Timeout.tv_sec := Seconds;
  Timeout.tv_usec := 0;
  Readfds.fd_count := 1;
  Readfds.fd_array[0] := Sock;

  { Attend au maximum Timeout secondes l'arrivée de données }
  Result := Select(0, @Readfds, nil, nil, @Timeout);
  if Result <> SOCKET_ERROR then
    { On peut continuer }
    if Readfds.fd_count = 0 then
      { On a dépassé le timeout. Il n'y a donc rien à lire }
      Result := 0
    else
      { Il y a des données à lire on va essayer de savoir quelle en est la taille }
      if IOCtlSocket(Sock, FIONREAD, Result) = SOCKET_ERROR then
        Result := SOCKET_ERROR;
end;

{ Fait un shutdown sur la socket.
  How peut prendre les valeurs SD_RECEIVE, SD_SEND ou SD_BOTH }

function CustomSocket.Shutdown(How: Integer): Integer;
begin
  Result := WinSock.Shutdown(Sock, How);
end;

{ Ferme la socket }

function CustomSocket.reStart: Integer;
begin
  { Recréation de la socket }
  Result := CloseSocket(Sock);
  Sock := Socket(AF_INET, SOCK_STREAM, 0);

  fStatus := ssInactive;
end;

{__________________________________________________________________________________________

 ConnectSocket
 __________________________________________________________________________________________}

{ Création de la socket serveur sur l'adresse locale spécifiée }

function ConnectSocket.CreateSocketServerEx(NetAddr: TInAddr; nPort: WORD; nListen: Integer): Integer;
begin
  { On ne peut pas se connecter car la socket n'est pas valide ou alors elle est déjà utilisée }
  if (Sock = INVALID_SOCKET) or (fStatus <> ssInactive) then begin
    Result := SOCKET_ERROR;
    Exit;
  end;

  { Rattachement de la socket }
  fSockAddr.sin_family := AF_INET;
  fSockAddr.sin_addr := NetAddr;
  fSockAddr.sin_port := htons(nPort);
  Result := Bind(Sock, fSockAddr, SizeOf(fSockAddr));

  { Mise en place de la file d'attente si le Bind c'est bien passé }
  if Result <> SOCKET_ERROR then begin
    Result := Listen(Sock, nListen);
    if Result <> SOCKET_ERROR then
      fStatus := ssListen;
  end;
end;

{ Création de la socket serveur sur n'importe quelle interface }

function ConnectSocket.CreateSocketServer(nPort: WORD; nListen: Integer): Integer;
var
  NetAddr: TInAddr;
begin
  NetAddr.S_addr := INADDR_ANY;
  Result := CreateSocketServerEx(NetAddr, nPort, nListen);
end;

{ Création de la socket serveur d'un service sur une adresse spécifiée }

function ConnectSocket.CreateSocketServiceEx(NetAddr: TInAddr; szName: PChar; nListen: Integer): Integer;
var
  ServEnt: PServEnt;
begin
  ServEnt := getServByName(szName, 'TCP');
  if ServEnt = nil then
    Result := SOCKET_ERROR
  else
    Result := CreateSocketServerEx(NetAddr, ServEnt^.s_port, nListen);
end;

{ Création de la socket serveur d'un service sur une interface choisie par le système }

function ConnectSocket.CreateSocketService(szName: PChar; nListen: Integer): Integer;
var
  NetAddr: TInAddr;
begin
  NetAddr.S_addr := INADDR_ANY;
  Result := CreateSocketServiceEx(NetAddr, szName, nListen);
end;

{ Accepte une connexion client }

function ConnectSocket.AcceptHost: CustomSocket;
var
  sout: TSockAddrIn;
  SizeAddr: Integer;
  Sock_io: TSocket;
begin
  Result := nil;

  { On ne peut pas accepter une connexions si la socket est invalide et si elle n'est en
    écoute }
  if (Sock = INVALID_SOCKET) or (fStatus <> ssListen) then
    Exit;

  SizeAddr := SizeOf(TSockAddrIn);

  Sock_io := Accept(Sock, PSockAddr(@sout), @SizeAddr);
  if Sock_io <> INVALID_SOCKET then
    Result := CustomSocket.ConnectedTo(Sock_io, @sout);
end;

{ Permet la connection à un hôte sur un port particulier. Si l'on veut se reconnecter
  à un port sans changer de serveur il suffit de passer nil dans szHostName. }

function ConnectSocket.ConnectHost(szHostName: PChar; nPort: WORD): Integer;
begin
  Result := SOCKET_ERROR;

  { On ne peut pas se connecter car la socket n'est pas valide ou alors on elle est
    déjà utilisée }
  if (Sock = INVALID_SOCKET) or (fStatus <> ssInactive) then
    Exit;

  { Si szHostName vaut nil on ne recherche pas de nouveau l'adresse de l'hôte }
  if szHostName <> nil then begin
    { Récupération des paramètres de l'hôte distant }
    fHost := GetHostByName(szHostName);
    if fHost = nil then
      Exit;
    fSockAddr.sin_family := AF_INET;
    CopyMemory(@fSockAddr.sin_addr.s_addr, fHost^.h_addr^, fHost^.h_length);
  end;

  fSockAddr.sin_port := htons(nPort);

  { Connexion de la socket }
  Result := Connect(Sock, fSockAddr, SizeOf(fSockAddr));
  if Result <> SOCKET_ERROR then
    fStatus := ssConnect;
end;

initialization
  { Démarre l'API Socket dans la version 2.0 }
  StartSocket(MAKEWORD(2, 0));

finalization
  { Arrête l'API Socket }
  StopSocket();
end.
