import { Request, Response, NextFunction, RequestHandler } from "express";

/**
 * O Express 4 NÃO captura erros lançados dentro de uma função async passada
 * pra .get()/.post()/etc — se a promise rejeitar (ex: sessionManager.requireSession
 * lançando "sessão não encontrada"), a requisição fica pendurada pra sempre,
 * sem nunca responder, porque ninguém chama res.send() nem next(erro).
 *
 * Esse wrapper resolve isso: qualquer erro (síncrono ou de promise rejeitada)
 * dentro do handler é automaticamente repassado pro errorHandler global,
 * que sempre responde algo (nem que seja um 500 com a mensagem do erro) em
 * vez de deixar o cliente esperando indefinidamente.
 */
export function asyncHandler(
  handler: (req: Request, res: Response, next: NextFunction) => Promise<void>
): RequestHandler {
  return (req, res, next) => {
    Promise.resolve(handler(req, res, next)).catch(next);
  };
}
