from fastapi import APIRouter, Request, Response, status
from fastapi.concurrency import run_in_threadpool

from app.api.deps import CurrentUser, limit_ip
from app.models.schemas import UserResponse
from app.services import users

router = APIRouter(prefix="/api/v1/users", tags=["users"])


@router.post(
    "/anonymous",
    response_model=UserResponse,
    status_code=status.HTTP_201_CREATED,
    dependencies=[limit_ip("register")],
)
async def create_anonymous_user(request: Request) -> UserResponse:
    """Register this device. The token is returned once: the app keeps it and sends it as a Bearer token.

    Unauthenticated by design (there is no login), so it is rate limited per client address.
    """
    user_id, token = users.create_anonymous(request.app.state.db)
    return UserResponse(user_id=user_id, token=token)


@router.delete("/me", status_code=status.HTTP_204_NO_CONTENT)
async def delete_me(request: Request, user_id: CurrentUser) -> Response:
    """Erase this user: every study, mask version and file, and the account itself. The token stops working."""
    await run_in_threadpool(users.delete_user, request.app.state.storage, request.app.state.db, user_id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)
