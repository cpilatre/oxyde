program Oxyde;

{$MODE Delphi}

{$APPTYPE CONSOLE}

{ Oxyde   : Serveur HTTP compatible completement avec la version 0.9 du protocole et
            en partie avec la version 1.0.
  Date    : Juin 2000
  Auteur  : Claude Pilatre }

uses SysUtils, Windows,
  Http in 'Http.pas',
  Thread in 'Thread.pas',
  Config in 'Config.pas',
  Stream in 'Stream.pas';

{$R *.res}

const
  SERVER_INFORMATION = SERVER_VERSION + ' (July 2000)';
  CONFIG_FILE_SERVER = 'conf/server.conf';

{ 'The main program' (balaise !!) }

var
  csServer: ConnectSocket;
  Params: ServerParams;
begin
  Writeln(SERVER_INFORMATION);

  { Récupération des paramètes du serveur }
  if not Init(ExtractFilePath(ParamStr(0)) + CONFIG_FILE_SERVER, Params) then begin
    Writeln('Error : (main) Init return false');
    Exit;
  end;

  { Création de la socket ... }
  csServer := ConnectSocket.Create();

  try
    { ... et démarrage de la socket }
    csServer.CreateSocketServerEx(Params.NetAddr, Params.Port, Params.Listen);
    if csServer.Status = ssInactive then
      Writeln('Error : CreateSocketServerEx() does not make server')
    else
      { Démarrage du serveur }
      while True do 
        RequestThread.Create(@Params, csServer.AcceptHost());
  finally
    csServer.Free();
    Params.Mime.Free();
  end;
end.
