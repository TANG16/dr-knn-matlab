function d = distmat( P, X, work, varargin )
%
% DISTMAT: Compute a pairwise distance matrix
%
% Usage:
%   DST = distmat( P, X, cfg, ... )
%
% Input:
%   P        - First data matrix. Each column vector is a data point.
%   X        - Second data matrix. Each column vector is a data point.
%   cfg      - Configuration data structure.
%
% Input (optional):
%   'tangVp',tangVp           - Tangent bases of prototypes
%   'tangVx',tangVx           - Tangent bases of testing data
%   'logfile',FID             - Output log file (default=stderr)
%
% Output:
%   DST      - Pairwise distance matrix
%
% $Revision$
% $Date$
%

% Copyright (C) 2008-2010 Mauricio Villegas (mvillegas AT iti.upv.es)
%
% This program is free software: you can redistribute it and/or modify
% it under the terms of the GNU General Public License as published by
% the Free Software Foundation, either version 3 of the License, or
% (at your option) any later version.
%
% This program is distributed in the hope that it will be useful,
% but WITHOUT ANY WARRANTY; without even the implied warranty of
% MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
% GNU General Public License for more details.
%
% You should have received a copy of the GNU General Public License
% along with this program. If not, see <http://www.gnu.org/licenses/>.

fn = 'distmat:';
minargs = 3;

if nargin==0
  d.dtype.euclidean = true;
  d.dtype.cosine = false;
  d.dtype.tangent = false;
  d.dtype.rtangent = false;
  d.dtype.otangent = false;
  d.dtype.atangent = false;
  d.dtype.hamming = false;
  return;
end

if ischar(P)
  unix(['echo "$Revision$* $Date$*" | sed "s/^:/' fn ' revision/g; s/ : /[/g; s/ (.*)/]/g;"']);
  return;
end

[ D, Np ] = size(P);
Nx = size(X,2);
d = [];

if isfield(work,'tangVp')
  tangVp = work.tangVp;
end
if isfield(work,'tangVx')
  tangVx = work.tangVx;
end

logfile = 2;

n = 1;
argerr = false;
while size(varargin,2)>0
  if ~ischar(varargin{n})
    argerr = true;
  elseif strcmp(varargin{n},'logfile') || ...
         strcmp(varargin{n},'tangVp') || ...
         strcmp(varargin{n},'tangVx')
    eval([varargin{n},'=varargin{n+1};']);
    if ~isnumeric(varargin{n+1})
      argerr = true;
    else
      n = n+2;
    end
  else
    argerr = true;
  end
  if argerr || n>size(varargin,2)
    break;
  end
end

if argerr
  fprintf(logfile,'%s error: incorrect input argument %d (%s,%g)\n',fn,n+minargs,varargin{n},varargin{n+1});
  return;
elseif nargin-size(varargin,2)~=minargs
  fprintf(logfile,'%s error: not enough input arguments\n',fn);
  return;
elseif Nx>0 && size(X,1)~=D
  fprintf(logfile,'%s error: dimensionality (rows) of both data matrices must be the same\n',fn);
  return;
elseif ~isfield(work,'dtype')
  fprintf(logfile,'%s error: dtype should be specified\n',fn);
  return;
elseif isfield(work.dtype,'tangent') && ~exist('tangVp','var') && ...
       ( work.dtype.tangent || work.dtype.atangent || work.dtype.rtangent )
  fprintf(logfile,'%s error: tangents of P should be given\n',fn);
  return;
elseif isfield(work.dtype,'tangent') && ~exist('tangVx','var') && Nx>0 && ...
       ( work.dtype.tangent || work.dtype.atangent || work.dtype.otangent )
  fprintf(logfile,'%s error: tangents of X should be given\n',fn);
  return;
elseif ( exist('tangVp','var') && mod(size(tangVp,2),Np)~=0 ) || ...
       ( exist('tangVx','var') && mod(size(tangVx,2),Nx)~=0 )
  fprintf(logfile,'%s error: number of tangents should be a multiple of the number of samples\n',fn);
  return;
end

dtype = work.dtype;
onesNp = ones(Np,1);
onesNx = ones(Nx,1);
onesD = ones(D,1);

cosnorm = true;
if isfield(work,'cosnorm')
  cosnorm = work.cosnorm;
end
normdist = false;
if isfield(work,'normdist')
  normdist = work.normdist;
end
torthonorm = false;
if isfield(work,'torthonorm')
  torthonorm = work.torthonorm;
end

if exist('tangVp','var') && ( dtype.rtangent || dtype.atangent || dtype.tangent )
  Lp = size(tangVp,2)/Np;
  if torthonorm || sum(sum(eye(Lp)-round(1000*tangVp(:,1:Lp)'*tangVp(:,1:Lp))./1000))~=0
    if ~torthonorm
      fprintf(logfile,'%s warning: tangVp not orthonormal, orthonormalizing ...\n',fn);
    end
    for nlp=1:Lp:size(tangVp,2)
      [ orthoVp, dummy ] = qr(tangVp(:,nlp:nlp+Lp-1),0);
      tangVp(:,nlp:nlp+Lp-1) = orthoVp;
    end
  end
end
if exist('tangVx','var') && ( dtype.otangent || dtype.atangent || dtype.tangent )
  Lx = size(tangVx,2)/Nx;
  if torthonorm || sum(sum(eye(Lx)-round(1000*tangVx(:,1:Lx)'*tangVx(:,1:Lx))./1000))~=0
    if ~torthonorm
      fprintf(logfile,'%s warning: tangVx not orthonormal, orthonormalizing ...\n',fn);
    end
    for nlx=1:Lx:size(tangVx,2)
      [ orthoVx, dummy ] = qr(tangVx(:,nlx:nlx+Lx-1),0);
      tangVx(:,nlx:nlx+Lx-1) = orthoVx;
    end
  end
end

if Nx>0

  % euclidean distance
  if dtype.euclidean
    x2 = sum((X.^2),1)';
    p2 = sum((P.^2),1);
    d = X'*P;
    d = x2(:,onesNp)+p2(onesNx,:)-d-d;
    if isfield(work,'sqrt') && work.sqrt
      d(d<0) = 0;
      d = sqrt(d);
    end
    if normdist
      d = (1/D).*d;
    end
  % cosine distance
  elseif dtype.cosine
    if cosnorm
      psd = sqrt(sum(P.*P,1));
      P = P./psd(onesD,:);
      xsd = sqrt(sum(X.*X,1));
      X = X./xsd(onesD,:);
    end
    if isfield(work,'cospos') && work.cospos
      d = 1-(X'*P+1)./2;
    else
      d = 1-X'*P;
    end
  % hamming distance
  elseif dtype.hamming
    lup = uint16([ ...
      0 1 1 2 1 2 2 3 1 2 2 3 2 3 3 4 1 2 2 3 2 3 ...
      3 4 2 3 3 4 3 4 4 5 1 2 2 3 2 3 3 4 2 3 3 4 ...
      3 4 4 5 2 3 3 4 3 4 4 5 3 4 4 5 4 5 5 6 1 2 ...
      2 3 2 3 3 4 2 3 3 4 3 4 4 5 2 3 3 4 3 4 4 5 ...
      3 4 4 5 4 5 5 6 2 3 3 4 3 4 4 5 3 4 4 5 4 5 ...
      5 6 3 4 4 5 4 5 5 6 4 5 5 6 5 6 6 7 1 2 2 3 ...
      2 3 3 4 2 3 3 4 3 4 4 5 2 3 3 4 3 4 4 5 3 4 ...
      4 5 4 5 5 6 2 3 3 4 3 4 4 5 3 4 4 5 4 5 5 6 ...
      3 4 4 5 4 5 5 6 4 5 5 6 5 6 6 7 2 3 3 4 3 4 ...
      4 5 3 4 4 5 4 5 5 6 3 4 4 5 4 5 5 6 4 5 5 6 ...
      5 6 6 7 3 4 4 5 4 5 5 6 4 5 5 6 5 6 6 7 4 5 ...
      5 6 5 6 6 7 5 6 6 7 6 7 7 8]);
    d = zeros(Nx,Np);
    for nx=1:Nx
      d(nx,:) = sum(lup(1+uint16(bitxor(P,X(:,nx(onesNp))))),1);
    end
    if normdist
      d = (1/(8*D)).*d;
    end
  % reference single sided tangent distance
  elseif dtype.rtangent
    d = zeros(Nx,Np);
    Lp = size(tangVp,2)/Np;
    nlp = 1;
    for np=1:Np
      dXP = X-P(:,np(onesNx));
      VdXP = tangVp(:,nlp:nlp+Lp-1)'*dXP;
      d(:,np) = (sum(dXP.*dXP,1)-sum(VdXP.*VdXP,1))';
      nlp = nlp+Lp;
    end
    if isfield(work,'sqrt') && work.sqrt
      d(d<0) = 0;
      d = sqrt(d);
    end
    if normdist
      d = (1/D).*d;
    end
  % observation single sided tangent distance
  elseif dtype.otangent
    d = zeros(Nx,Np);
    Lx = size(tangVx,2)/Nx;
    nlx = 1;
    for nx=1:Nx
      dXP = X(:,nx(onesNp))-P;
      VdXP = tangVx(:,nlx:nlx+Lx-1)'*dXP;
      d(nx,:) = sum(dXP.*dXP,1)-sum(VdXP.*VdXP,1);
      nlx = nlx+Lx;
    end
    if isfield(work,'sqrt') && work.sqrt
      d(d<0) = 0;
      d = sqrt(d);
    end
    if normdist
      d = (1/D).*d;
    end
  % average single sided tangent distance
  elseif dtype.atangent
    d = zeros(Nx,Np);
    Lp = size(tangVp,2)/Np;
    nlp = 1;
    for np=1:Np
      dXP = X-P(:,np(onesNx));
      VdXP = tangVp(:,nlp:nlp+Lp-1)'*dXP;
      d(:,np) = (sum(dXP.*dXP,1)-0.5*sum(VdXP.*VdXP,1))';
      nlp = nlp+Lp;
    end
    Lx = size(tangVx,2)/Nx;
    nlx = 1;
    for nx=1:Nx
      dXP = X(:,nx(onesNp))-P;
      VdXP = tangVx(:,nlx:nlx+Lx-1)'*dXP;
      d(nx,:) = d(nx,:)-0.5*sum(VdXP.*VdXP,1);
      nlx = nlx+Lx;
    end
    if isfield(work,'sqrt') && work.sqrt
      d(d<0) = 0;
      d = sqrt(d);
    end
    if normdist
      d = (1/D).*d;
    end
  % tangent distance
  elseif dtype.tangent
    d = zeros(Nx,Np);
    Lp = size(tangVp,2)/Np;
    Lx = size(tangVx,2)/Nx;
    tangVpp = zeros(Lp,Lp*Np);
    itangVpp = zeros(Lp,Lp*Np);
    tangVxx = zeros(Lx,Lx*Nx);
    itangVxx = zeros(Lx,Lx*Nx);
    nlp = 1;
    for np=1:Np
      sel = nlp:nlp+Lp-1;
      Vp = tangVp(:,sel);
      tangVpp(:,sel) = Vp'*Vp;
      itangVpp(:,sel) = inv(tangVpp(:,sel));
      nlp = nlp+Lp;
    end
    nlx = 1;
    for nx=1:Nx
      sel = nlx:nlx+Lx-1;
      Vx = tangVx(:,sel);
      tangVxx(:,sel) = Vx'*Vx;
      itangVxx(:,sel) = inv(tangVxx(:,sel));
      nlx = nlx+Lx;
    end
    nlx = 1;
    for nx=1:Nx
      sel = nlx:nlx+Lx-1;
      nlx = nlx+Lx;
      Vx = tangVx(:,sel);
      Vxx = tangVxx(:,sel);
      iVxx = itangVxx(:,sel);
      x = X(:,nx);
      nlp = 1;
      for np=1:Np
        sel = nlp:nlp+Lp-1;
        nlp = nlp+Lp;
        Vp = tangVp(:,sel);
        Vpp = tangVpp(:,sel);
        iVpp = itangVpp(:,sel);
        p = P(:,np);
        Vpx = Vp'*Vx;
        Alp = (Vpx*iVxx*Vx'-Vp')*(x-p);
        Arp = Vpx*iVxx*Vpx'-Vpp;
        Alx = (Vpx'*iVpp*Vp'-Vx')*(x-p);
        Arx = Vxx-Vpx'*iVpp*Vpx;
        ap = Arp\Alp;
        ax = Arx\Alx;
        xx = x+Vx*ax;
        pp = p+Vp*ap;
        d(nx,np) = (xx-pp)'*(xx-pp);
      end
    end
    if isfield(work,'sqrt') && work.sqrt
      d(d<0) = 0;
      d = sqrt(d);
    end
    if normdist
      d = (1/D).*d;
    end
  end

else

  % euclidean distance
  if dtype.euclidean
    p2 = sum((P.^2),1);
    d = P'*P;
    d = p2(onesNp,:)'+p2(onesNp,:)-d-d;
    if isfield(work,'sqrt') && work.sqrt
      d(d<0) = 0;
      d = sqrt(d);
    end
    if normdist
      d = (1/D).*d;
    end
  % cosine distance
  elseif dtype.cosine
    if cosnorm
      psd = sqrt(sum(P.*P,1));
      P = P./psd(onesD,:);
    end
    if isfield(work,'cospos') && work.cospos
      d = 1-(P'*P+1)./2;
    else
      d = 1-P'*P;
    end
  % hamming distance
  elseif dtype.hamming
    lup = uint16([ ...
      0 1 1 2 1 2 2 3 1 2 2 3 2 3 3 4 1 2 2 3 2 3 ...
      3 4 2 3 3 4 3 4 4 5 1 2 2 3 2 3 3 4 2 3 3 4 ...
      3 4 4 5 2 3 3 4 3 4 4 5 3 4 4 5 4 5 5 6 1 2 ...
      2 3 2 3 3 4 2 3 3 4 3 4 4 5 2 3 3 4 3 4 4 5 ...
      3 4 4 5 4 5 5 6 2 3 3 4 3 4 4 5 3 4 4 5 4 5 ...
      5 6 3 4 4 5 4 5 5 6 4 5 5 6 5 6 6 7 1 2 2 3 ...
      2 3 3 4 2 3 3 4 3 4 4 5 2 3 3 4 3 4 4 5 3 4 ...
      4 5 4 5 5 6 2 3 3 4 3 4 4 5 3 4 4 5 4 5 5 6 ...
      3 4 4 5 4 5 5 6 4 5 5 6 5 6 6 7 2 3 3 4 3 4 ...
      4 5 3 4 4 5 4 5 5 6 3 4 4 5 4 5 5 6 4 5 5 6 ...
      5 6 6 7 3 4 4 5 4 5 5 6 4 5 5 6 5 6 6 7 4 5 ...
      5 6 5 6 6 7 5 6 6 7 6 7 7 8]);
    d = zeros(Np,Np);
    for nx=1:Np
      d(nx,:) = sum(lup(1+uint16(bitxor(P,P(:,nx(onesNp))))),1);
    end
    if normdist
      d = (1/(8*D)).*d;
    end
  elseif dtype.rtangent || dtype.otangent || dtype.atangent || dtype.tangent
    fprintf(logfile,'%s error: not implemented\n',fn);
  end

end

if isfield(work,'nozero') && work.nozero
  d(d<eps) = eps;
elseif isfield(work,'noneg') && work.noneg
  d(d<0) = 0;
end